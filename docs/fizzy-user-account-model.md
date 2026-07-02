# Fizzy's User / Account Model

*Captured from the actual source of [`basecamp/fizzy`](https://github.com/basecamp/fizzy)
(`main`), as reference for the Writer Group site. This documents the
**membership + tenancy + access** layer that sits under the auth protocol in
[`fizzy-authentication.md`](./fizzy-authentication.md).*

> **Scope note (per request):** the **account-creation flow** — `Account`'s
> `create_with_owner` / join-code seeding, i.e. the "each user creates a group"
> path — is **intentionally left out** of this doc. What's captured here is the
> steady-state shape of Users, Accounts, Roles, and Access, not how a new
> account is born.

Files captured: `app/models/user.rb`, `app/models/account.rb`,
`app/models/user/role.rb`, `app/models/access.rb`,
`app/models/user/accessor.rb`. (`Identity` lives in the auth doc.)

---

## 1. The four layers

```
Identity ──< User >── Account            User ──< Access >── Board
 (global      (membership   (tenant)      (member    (grant)   (resource)
  login)       per account)                 → per-board access)
```

| Model | Role in the system |
|-------|-------------------|
| **`Identity`** | Global, email-based login. Owns credentials. (See auth doc.) |
| **`User`** | A **membership** — one per account. Carries name, role, active flag, verification. `belongs_to :account`, `belongs_to :identity` (optional). |
| **`Account`** | The **tenant**. Owns boards, cards, users, etc. |
| **`Access`** | A join row granting one `User` access to one `Board` (with a watching/involvement level). The per-resource authorization grain. |

The load-bearing idea: **`User` is not a person — it's a person's membership in
one account.** The person is the `Identity`. `identity` is `optional: true` on
`User`, so a membership can exist detached from any login (e.g. the `System`
user, or a deactivated user whose identity was nulled).

---

## 2. `User` — the membership record

```ruby
class User < ApplicationRecord
  include Accessor, Assignee, Attachable, Avatar, Configurable, EmailAddressChangeable,
    Mentionable, Named, Notifiable, Role, Searcher, Watcher
  include Timelined # Depends on Accessor

  belongs_to :account
  belongs_to :identity, optional: true

  validates :name, presence: true

  has_many :comments, inverse_of: :creator, dependent: :destroy

  has_many :filters, foreign_key: :creator_id, inverse_of: :creator, dependent: :destroy
  has_many :closures, dependent: :nullify
  has_many :pins, dependent: :destroy
  has_many :pinned_cards, through: :pins, source: :card
  has_many :data_exports, class_name: "User::DataExport", dependent: :destroy

  def deactivate
    transaction do
      accesses.destroy_all
      update! active: false, identity: nil
      close_remote_connections
    end
  end

  def setup?
    name != identity.email_address
  end

  def verified?
    verified_at.present?
  end

  def verify
    update!(verified_at: Time.current) unless verified?
  end

  private
    def close_remote_connections
      ActionCable.server.remote_connections.where(current_user: self).disconnect(reconnect: false)
    end
end
```

Notes:
- **Behavior is composed from ~13 concerns.** `Role` (permissions), `Accessor`
  (board access), `Assignee`, `Mentionable`, `Named`, `Notifiable`, `Watcher`,
  etc. The class body itself is thin — it's mostly membership lifecycle.
- **`deactivate`** is the mirror of `Identity#deactivate_users`: it destroys the
  user's `accesses`, flips `active: false`, **nulls the `identity`** (severs the
  login), and disconnects live ActionCable connections — all in a transaction.
  The membership record survives; it just can't log in or reach anything.
- **`setup?`** — a user is "set up" once their `name` differs from their
  identity's email (i.e. they've personalized it beyond the auto-provisioned
  default).
- **`verified?` / `verify`** — a `verified_at` timestamp gate, set on demand.

---

## 3. `User::Role` — roles and the permission vocabulary

```ruby
module User::Role
  extend ActiveSupport::Concern

  included do
    enum :role, %i[ owner admin member system ].index_by(&:itself), scopes: false

    scope :owner, -> { where(active: true, role: :owner) }
    scope :admin, -> { where(active: true, role: %i[ owner admin ]) }
    scope :member, -> { where(active: true, role: :member) }
    scope :active, -> { where(active: true, role: %i[ owner admin member ]) }

    def admin?
      super || owner?
    end
  end

  def can_change?(other)
    (admin? && !other.owner?) || other == self
  end

  def can_administer?(other)
    admin? && !other.owner? && other != self
  end

  def can_administer_board?(board)
    admin? || board.creator == self
  end

  def can_administer_card?(card)
    admin? || card.creator == self
  end
end
```

Roles: **`owner`, `admin`, `member`, `system`.** Key design choices:
- **`system` is a role, not active.** The `active` scope is
  `owner|admin|member` — `system` (the account's automated actor) is excluded
  from "active users." Every account has exactly one, found via
  `Account#system_user`.
- **`admin?` is inclusive of `owner`** (`super || owner?`), so owners pass every
  admin check without enumerating both.
- **Permissions are plain predicate methods, not a policy framework:**
  - `can_change?(other)` — admins can change anyone except owners; anyone can
    change themselves.
  - `can_administer?(other)` — admins can administer non-owner others (but not
    themselves).
  - `can_administer_board?` / `can_administer_card?` — admin **or** the creator
    of that resource. This "**admin or creator**" rule is the recurring
    authorization primitive.

---

## 4. `Account` — the tenant

```ruby
class Account < ApplicationRecord
  include Account::Storage, Cancellable, Entropic, Incineratable, MultiTenantable, Searchable, Seedeable

  has_one :join_code, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :boards, dependent: :destroy
  has_many :cards, dependent: :destroy
  has_many :webhooks, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :columns, dependent: :destroy
  has_many :entropies, dependent: :destroy
  has_many :exports, class_name: "Account::Export", dependent: :destroy
  has_many :imports, class_name: "Account::Import", dependent: :destroy

  scope :importing, -> { left_joins(:imports).where(account_imports: { status: %i[pending processing failed] }) }
  scope :active, -> { where.missing(:cancellation).and(where.not(id: importing)) }

  validates :name, presence: true

  def slug
    "/#{AccountSlug.encode(external_account_id)}"
  end

  def account
    self
  end

  def system_user
    users.find_by!(role: :system)
  end

  def active?
    !cancelled? && !importing?
  end

  def importing?
    imports.where(status: %i[pending processing failed]).exists?
  end
end
```

> *Omitted per scope:* the `create_with_owner` class method and the
> `before_create :assign_external_account_id` / `after_create :create_join_code`
> callbacks that provision a brand-new account and its first owner. That's the
> "user creates a group" path we're deliberately not documenting here.

Notes on the steady-state shape:
- The tenant **owns everything** (`users`, `boards`, `cards`, `columns`, `tags`,
  `webhooks`, exports/imports) with `dependent: :destroy` — deleting an account
  cascades the whole workspace.
- **`account` returns `self`.** This lets code call `.account` uniformly on a
  `User`, an `Access`, or an `Account` and always land on the tenant — handy for
  the `Current`/tenant-scoping machinery.
- **`system_user`** — the automated actor (`role: :system`) every account has.
- **Lifecycle scopes:** `active` = not cancelled **and** not importing;
  mirrored by the `active?` / `importing?` predicates. Cancellation and import
  are the two states that take an account "offline."
- Multi-tenancy and search are pulled in as concerns
  (`MultiTenantable`, `Searchable`), plus storage, cancellation, and entropy
  (secret rotation) mixins.

---

## 5. `Access` + `User::Accessor` — per-resource authorization

Membership in an account is not enough to see a board; a `User` needs an
`Access` row. This is the fine grain beneath the role system.

```ruby
class Access < ApplicationRecord
  belongs_to :account, default: -> { user.account }
  belongs_to :board, touch: true
  belongs_to :user, touch: true

  enum :involvement, %i[ access_only watching ].index_by(&:itself), default: :access_only

  scope :ordered_by_recently_accessed, -> { order(accessed_at: :desc) }

  after_destroy_commit :clean_inaccessible_data_later

  def accessed
    touch :accessed_at unless recently_accessed?
  end

  private
    def recently_accessed?
      accessed_at&.> 5.minutes.ago
    end

    def clean_inaccessible_data_later
      Board::CleanInaccessibleDataJob.perform_later(user, board) unless user.destroyed?
    end
end
```

```ruby
module User::Accessor
  extend ActiveSupport::Concern

  included do
    has_many :accesses, dependent: :destroy
    has_many :boards, through: :accesses
    has_many :accessible_columns, through: :boards, source: :columns
    has_many :accessible_cards, through: :boards, source: :cards
    has_many :accessible_comments, through: :accessible_cards, source: :comments

    after_create_commit :grant_access_to_boards, unless: :system?
  end

  def draft_new_card_in(board)
    board.cards.find_or_initialize_by(creator: self, status: "drafted").tap do |card|
      card.update!(created_at: Time.current, updated_at: Time.current, last_active_at: Time.current)
    end
  end

  private
    def grant_access_to_boards
      Access.insert_all account.boards.all_access.ids.collect { |board_id| { id: ActiveRecord::Type::Uuid.generate, board_id: board_id, user_id: id, account_id: account.id } }
    end
end
```

How access works:
- **`Access` = (user, board, account, involvement).** `involvement` is
  `access_only` or `watching` (watching adds notifications on top of access).
  Both `board` and `user` are `touch: true`, so granting/revoking bumps their
  caches.
- **A user reaches content *through* their accesses:** `boards →
  accessible_columns → accessible_cards → accessible_comments`. No access row,
  no visibility — even within the same account.
- **New non-system users are auto-granted** to every `all_access` board on
  create (`grant_access_to_boards` via bulk `insert_all`). System users are
  skipped.
- **Revoking access is a data event:** destroying an `Access` enqueues
  `Board::CleanInaccessibleDataJob` to scrub anything the user should no longer
  hold. And `User#deactivate` `destroy_all`s accesses first.
- **`accessed`** throttles `accessed_at` updates to once per 5 minutes — cheap
  "recently viewed" ordering without write amplification.

---

## 6. Lifecycle summary

- **Provision** *(out of scope here)* → a `User` is created in an account with a
  role; if non-system, it's auto-granted access to all-access boards.
- **Set up** → user personalizes `name` (`setup?` flips true); optionally
  `verify`d (`verified_at`).
- **Operate** → role predicates (`admin?`, `can_administer_board?`) gate
  actions; `Access` rows gate visibility; `involvement` controls watching.
- **Deactivate** → `User#deactivate`: destroy accesses, `active: false`, null the
  identity, disconnect live sockets. Membership record persists, login severed.
- **Account offline** → `cancelled?` or `importing?` → account drops out of the
  `active` scope.

---

## 7. Mapping to Writer Group

Lines up directly with the sketch in [`data-model.md`](./data-model.md):

| Fizzy | Writer Group equivalent | Notes |
|-------|------------------------|-------|
| `Identity` | `Person` | Global login, one email. |
| `User` | `Membership` | Per-group membership; carries role + name. |
| `Account` | `Group` (bucket) | The tenant / community space. |
| `Access` | *(new)* per-board/board-access grant | Adopt if boards should be individually access-controlled rather than group-wide. |
| `User::Role` (owner/admin/member/system) | group roles | The **"admin or creator"** rule is worth copying wholesale. |

Two patterns especially worth carrying over:
1. **Identity ≠ membership.** Keeping credentials on `Person` and role/access on
   `Membership` is what makes an author belonging to multiple groups clean.
2. **"Admin or creator" authorization** as the default predicate for editing a
   board/message/doc — simple, no policy framework needed.

*Not captured:* `Account.create_with_owner` and join-code onboarding (excluded
per scope), plus the many secondary `User` concerns (`Assignee`, `Mentionable`,
`Notifiable`, `Watcher`, …) and `Account` mixins (`Cancellable`, `Entropic`,
`Incineratable`, `MultiTenantable`, …). Pull those files if you need them.

## Sources
- [basecamp/fizzy (GitHub)](https://github.com/basecamp/fizzy)
- [user.rb](https://github.com/basecamp/fizzy/blob/main/app/models/user.rb)
- [account.rb](https://github.com/basecamp/fizzy/blob/main/app/models/account.rb)
- [user/role.rb](https://github.com/basecamp/fizzy/blob/main/app/models/user/role.rb)
- [access.rb](https://github.com/basecamp/fizzy/blob/main/app/models/access.rb)
- [user/accessor.rb](https://github.com/basecamp/fizzy/blob/main/app/models/user/accessor.rb)
