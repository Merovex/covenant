# Fizzy's Authentication Protocol

*Captured from the actual source of [`basecamp/fizzy`](https://github.com/basecamp/fizzy)
(`main`), for reference while designing the Writer Group site's auth. Fizzy is
37signals' open-source Kanban app; its auth is **passwordless, identity-centric,
and multi-tenant**. Code blocks below are verbatim from the repo.*

Source files captured: `app/controllers/concerns/authentication.rb`,
`app/models/identity.rb`, `app/models/session.rb`, `app/models/current.rb`.

---

## 1. The model split (why there are three "user-ish" models)

| Model | What it is | Key associations |
|-------|-----------|------------------|
| **`Identity`** | The global, email-based login. *Who you are* across all tenants. Owns credentials. | `has_many :users`, `has_many :accounts, through: :users`, `has_many :sessions`, `has_many :magic_links`, `has_many :access_tokens`, `has_passkeys` |
| **`User`** | A **membership** — one per account you belong to. Per-tenant identity/authorization. | belongs to an `Account` and an `Identity` |
| **`Account`** | The tenant. | `has_many :users` |

One email (one `Identity`) → many `User` memberships → many `Account`s.
**Credentials live on `Identity`; tenant membership lives on `User`.** That
split is the core idea: *authenticate globally, authorize per-tenant.*

```ruby
class Identity < ApplicationRecord
  include Joinable, Transferable

  has_passkeys name: :email_address, display_name: -> { Current.user&.name || email_address }

  has_many :access_tokens, dependent: :destroy
  has_many :magic_links, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :users, dependent: :nullify
  has_many :accounts, through: :users

  has_one_attached :avatar, dependent: :purge_later

  before_destroy :deactivate_users, prepend: true

  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }
  normalizes :email_address, with: ->(value) { value.strip.downcase.presence }

  def self.find_by_permissable_access_token(token, method:)
    if (access_token = AccessToken.find_by(token: token)) && access_token.allows?(method)
      access_token.identity
    end
  end

  def send_magic_link(**attributes)
    attributes[:purpose] = attributes.delete(:for) if attributes.key?(:for)

    magic_links.create!(attributes).tap do |magic_link|
      MagicLinkMailer.sign_in_instructions(magic_link).deliver_later
    end
  end

  def users_with_active_accounts
    users.joins(:account).merge(Account.active).includes(:account)
  end

  private
    def deactivate_users
      users.find_each(&:deactivate)
    end
end
```

Notes worth stealing:
- **No `has_secure_password`.** Fizzy has no email+password path at all.
- Email is **normalized** (strip + downcase) and format-validated — the identity
  key is a clean canonical email.
- Destroying an `Identity` **nullifies** its users and deactivates them
  (`dependent: :nullify` + `deactivate_users`) — memberships survive as records,
  they just lose their login. Sessions/magic-links/tokens are destroyed.

---

## 2. `Current` — request-scoped state and tenant resolution

`Current` is where session → identity → user → account get wired together, and
it's the clever bit: setting the session cascades into resolving *which* `User`
you are **within the current account**.

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :identity, :account
  attribute :http_method, :request_id, :user_agent, :ip_address, :referrer

  def session=(value)
    super(value)

    if value.present?
      self.identity = session.identity
    end
  end

  def identity=(identity)
    super(identity)

    if identity.present?
      self.user = identity.users.find_by(account: account)
    end
  end

  def with_account(value, &)
    with(account: value, &)
  end

  def without_account(&)
    with(account: nil, &)
  end
end
```

The cascade: **`Current.session=` → sets `Current.identity` → looks up
`Current.user` scoped to `Current.account`.** So the same `Identity` resolves to
a different `User` depending on which tenant the request is in. `Account` must
therefore be established *before* the session (see the before_action order below).

`Session` itself is deliberately trivial — the envelope, not the logic:

```ruby
class Session < ApplicationRecord
  belongs_to :identity
end
```

---

## 3. The concern — the whole protocol

This is `app/controllers/concerns/authentication.rb`, verbatim. Everything below
is commentary on it.

```ruby
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_account # Checking and setting account must happen first
    before_action :require_authentication
    helper_method :authenticated?
    helper_method :email_address_pending_authentication

    etag { Current.identity.id if authenticated? }

    include Authentication::ViaMagicLink, LoginHelper
  end

  class_methods do
    def require_unauthenticated_access(**options)
      allow_unauthenticated_access **options
      before_action :redirect_authenticated_user, **options
    end

    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      before_action :resume_session, **options
      allow_unauthorized_access **options
    end

    def disallow_account_scope(**options)
      skip_before_action :require_account, **options
      before_action :redirect_tenanted_request, **options
    end
  end

  private
    def authenticated?
      Current.identity.present?
    end

    def require_account
      unless Current.account.present?
        redirect_to main_app.session_menu_path(script_name: nil)
      end
    end

    def require_authentication
      resume_session || authenticate_by_bearer_token || request_authentication
    end

    def resume_session
      if session = find_session_by_cookie
        set_current_session session
      end
    end

    def find_session_by_cookie
      Session.find_signed(cookies.signed[:session_token])
    end

    def authenticate_by_bearer_token
      if request.authorization.to_s.include?("Bearer")
        if bearer_token_authenticatable_request?
          authenticate_or_request_with_http_token do |token|
            if identity = Identity.find_by_permissable_access_token(token, method: request.method)
              Current.identity = identity
            end
          end
        else
          request_http_token_authentication
        end
      end
    end

    def bearer_token_authenticatable_request?
      request.format.json?
    end

    def request_authentication
      if Current.account.present?
        session[:return_to_after_authenticating] = request.url
      end

      redirect_to_login_url
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || landing_url
    end

    def redirect_authenticated_user
      redirect_to main_app.root_url if authenticated?
    end

    def redirect_tenanted_request
      redirect_to main_app.root_url if Current.account.present?
    end

    def start_new_session_for(identity)
      identity.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        set_current_session session
      end
    end

    def set_current_session(session)
      Current.session = session
      cookies.signed.permanent[:session_token] = { value: session.signed_id, httponly: true, same_site: :lax }
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_token)
    end

    def session_token
      cookies[:session_token]
    end
end
```

---

## 4. The protocol, step by step

### Every request runs two gates, in order
1. **`require_account`** — resolve the tenant first. If there's no
   `Current.account`, bounce to the session/account menu
   (`session_menu_path`). *Account must be set before identity so that
   `Current.identity=` can resolve the right per-account `User`.*
2. **`require_authentication`** — a three-way fallback chain:
   ```ruby
   resume_session || authenticate_by_bearer_token || request_authentication
   ```

### Path A — cookie session (the human path)
- `resume_session` reads the **signed** `:session_token` cookie and does
  `Session.find_signed(...)`.
- On hit, `set_current_session` sets `Current.session` (which cascades to
  identity → user) and **re-issues** the cookie as
  **`signed.permanent`, `httponly: true`, `same_site: :lax`**, valued with the
  session's `signed_id`.

### Path B — bearer token (the API path)
- Only for **JSON requests** (`bearer_token_authenticatable_request?` →
  `request.format.json?`) carrying an `Authorization: Bearer …` header.
- Token is validated by `Identity.find_by_permissable_access_token(token,
  method: request.method)` — which checks the token exists **and**
  `access_token.allows?(method)` (per-HTTP-method permissions). On success it
  sets `Current.identity` directly (no cookie, stateless).
- A Bearer header on a **non-JSON** request triggers
  `request_http_token_authentication` (401), rather than falling through.

### Path C — no credentials → request authentication
- `request_authentication` stashes `request.url` in
  `session[:return_to_after_authenticating]` (only if a tenant is present),
  then `redirect_to_login_url`.
- After a successful sign-in, `after_authentication_url` pops that value (or
  falls back to `landing_url`) so you land back where you were headed.

### Establishing a session (sign-in)
```ruby
start_new_session_for(identity)
  → identity.sessions.create!(user_agent:, ip_address:)   # records UA + IP
  → set_current_session(session)                          # sets cookie + Current
```
The actual *proof of identity* that precedes this comes from one of the three
passwordless mechanisms (§5).

### Sign-out
```ruby
terminate_session  # destroys the Session row, deletes the cookie
```

### Class-level toggles (how controllers opt in/out)
- **`allow_unauthenticated_access`** — skip `require_authentication` but still
  `resume_session` (so `Current` is populated if you *are* logged in) and allow
  unauthorized access.
- **`require_unauthenticated_access`** — the above **plus**
  `redirect_authenticated_user` (e.g. keep logged-in users off the login page).
- **`disallow_account_scope`** — skip `require_account` and
  `redirect_tenanted_request` (for global, non-tenant pages like the account
  chooser).

---

## 5. The three passwordless credential types

All belong to `Identity`. The concern above consumes them; the credential
ceremonies live in their own models/concerns (`Authentication::ViaMagicLink` is
mixed into the concern).

1. **Magic links** — `identity.send_magic_link(...)` creates a `MagicLink` and
   emails `MagicLinkMailer.sign_in_instructions`. Supports a `purpose`/`for`
   attribute (sign-in vs other flows). A `QrCodeLink` model exists for
   cross-device hand-off. *Primary human sign-in.*
2. **Passkeys / WebAuthn** — `has_passkeys name: :email_address, display_name:
   -> { Current.user&.name || email_address }`. Biometric/hardware path.
3. **Bearer access tokens** — `AccessToken` records with per-HTTP-method
   permissions (`allows?(method)`); stateless API auth.

---

## 6. Summary — what to carry into Writer Group

- **Drop passwords.** Identity + magic link (email) is the minimum viable human
  path; passkeys and API tokens layer on without changing the session core.
- **Split `Identity` (global login) from `User` (per-group membership).** Even if
  the Writer Group starts single-tenant, this split is what makes multi-group
  ("boardroom of author groups") clean later. Maps directly onto our
  `Person`/`Membership`/`Group` sketch in [`data-model.md`](./data-model.md):
  `Identity` ≈ `Person`, `User` ≈ `Membership`, `Account` ≈ `Group` (bucket).
- **Resolve tenant before identity.** `require_account` runs before
  `require_authentication`; `Current` cascades session → identity → account-scoped
  user.
- **Session = signed, permanent, httponly, SameSite=Lax cookie** over a trivial
  `Session` row that records UA + IP. `Session.find_signed` on each request.
- **One `require_authentication` chain** with three fallbacks (cookie → bearer →
  redirect), and clean class-macro opt-outs for public/login/global pages.

---

*Captured verbatim from `basecamp/fizzy@main`. Not read in full: the
`Authentication::ViaMagicLink` concern, `MagicLink`/`AccessToken`/`passkey/`
models, and `LoginHelper` — so magic-link TTLs, token expiry, and the passkey
ceremony aren't documented here. Pull those files if you need those specifics.*

## Sources
- [basecamp/fizzy (GitHub)](https://github.com/basecamp/fizzy)
- [authentication.rb](https://github.com/basecamp/fizzy/blob/main/app/controllers/concerns/authentication.rb)
- [identity.rb](https://github.com/basecamp/fizzy/blob/main/app/models/identity.rb)
- [current.rb](https://github.com/basecamp/fizzy/blob/main/app/models/current.rb)
- [session.rb](https://github.com/basecamp/fizzy/blob/main/app/models/session.rb)
