---
type: reference
title: Support Desk — Licenses & Tickets (implementation plan)
status: active
tags: [rails, licenses, tickets, email, action-mailbox, action-mailer, ses, record-recordable, theme]
created: 2026-07-22
updated: 2026-07-22
sources: [decisions/0006-record-recordable-generic-spine.md, decisions/0007-versioned-recordables.md, decisions/0008-email-relay-amazon-ses.md, decisions/0009-support-desk-customers-licenses-tickets.md, decisions/0010-inbound-email-action-mailbox-ses.md, concepts/css-architecture.md]
---

# Support Desk — Licenses & Tickets (implementation plan)

A self-contained build plan so work can resume from a clean context. Two
features on top of the existing app: **License tracking** and **Ticket
management** (email in + email out). Both hang off the existing
**Record/Recordable** spine ([[0006-record-recordable-generic-spine]],
[[0007-versioned-recordables]]). Decisions are recorded in
[[0009-support-desk-customers-licenses-tickets]] and
[[0010-inbound-email-action-mailbox-ses]].

> **App naming:** the repo/app is **Covenant**. The docs and CSS were templated
> from the sibling **Alcovo** app, so older pages still say "Alcovo" — treat
> those as the same codebase.

## Goal & scope

- Keep every existing model (Post, Message, Comment, ChatLine, Boost, Category,
  User, …). This is **additive**.
- Storage stays **SQLite** (already the adapter — nothing to change).
- Accent theme becomes **Pine** (from the marketing site), applied by
  repointing color tokens only.
- CSS stays **CUBE/BEM** per [[css-architecture]] — new standard blocks, tokens
  only, demoed at `/theme`.
- **Single-tenant** — there is no `accounts` table and no `account_id` anywhere;
  do **not** add tenancy. (The `Person/User/Account` vocabulary in
  [[domain-vocabulary]] is notional; the real identity table is `users` =
  `email_address`, `name`, `role`.)

## The four new models

| Model | Kind | On the spine? | Rich text | Notes |
|-------|------|---------------|-----------|-------|
| **Customer** | plain AR table (like `Category`) | no | no | the "collector" — external party who owns licenses and files tickets. `has_many :licenses, :tickets`. Not a `User`. |
| **License** | recordable (`include Recordable`) | yes | no | structured license row; versioned so renewals/status changes are history. |
| **Ticket** | recordable (`include Recordable`) | yes | **yes** (`content`) | the *bucket* + the **customer's opening email**. `title`, `status`, `customer_id`. |
| **Reply** | recordable (`include Recordable`) | yes | **yes** (`content`) | every message *after* the opener (inbound or outbound email). Threaded under the Ticket's record via `records.parent_id`. |

Design notes:

- **Not `Publishable`.** License/Ticket/Reply have no draft→publish regime and
  no shared `Body`. They `include Recordable` directly. Ticket and Reply carry
  rich text the way `Comment` does — `has_rich_text :content` on the version,
  and a `build_successor` that copies the body forward on action-only versions.
- **Immutable like `Comment`** (`mutable? = false`): every edit/status change/
  email is a permanent version → free audit trail.
- **Threading reuses the spine.** A Reply's `record.parent_id` = the Ticket's
  `record.id`, exactly how comments hang off a post today. `Ticket#replies`
  mirrors `Record#comments`.
- **`Reply.creator_id` is nullable** — an inbound customer email has no `User`
  author. Re-declare the association to allow it (see below).

## Schema (migrations, in order)

Action Storage / Action Text / Action Mailbox tables already exist. Add:

### 1. `customers` (plain)
```
customers
  name           :string  null: false
  email          :string  null: false        # index unique
  company        :string
  notes          :text
  timestamps
  index :email, unique: true
```

### 2. `licenses` (recordable version table)
```
licenses
  record_id      :integer null: false         # spine cursor target
  creator_id     :integer null: false         # FK users
  event          :string  null: false  default: "created"
  customer_id    :integer null: false         # FK customers
  license_key    :string  null: false
  product        :string  null: false
  seats          :integer null: false  default: 1
  issued_at      :datetime
  expires_at     :datetime
  status         :string  null: false  default: "active"   # active|suspended|expired|revoked
  timestamps
  index [:record_id, :id]
  index :creator_id
  index :customer_id
  add_foreign_key :records, :users(creator_id), :customers
```
> `license_key` uniqueness is **per current license**, not per version row
> (versions repeat the key). Enforce with a validation scoped to
> `License.current` (see Open items), not a bare DB unique index.

### 3. `tickets` (recordable version table; rich text opener)
```
tickets
  record_id      :integer null: false
  creator_id     :integer null: false         # FK users (who opened it in-app; may be a system user for inbound)
  event          :string  null: false  default: "created"
  customer_id    :integer null: false         # FK customers
  title          :string  null: false
  status         :string  null: false  default: "open"      # open|pending|on_hold|resolved|closed
  from_address   :string                                    # opener's From (usually customer.email)
  message_id     :string                                    # opener Message-ID (threading + ingest dedup)
  timestamps
  index [:record_id, :id]; index :creator_id; index :customer_id
  index :message_id, unique: true          # nullable-unique: dedup inbound openers
  add_foreign_key :records, :users(creator_id), :customers
```
Opener body → Action Text (`has_rich_text :content`), no column.

### 4. `replies` (recordable version table; rich text body + email metadata)
```
replies
  record_id      :integer null: false
  creator_id     :integer                      # NULLABLE — inbound has no User author
  event          :string  null: false  default: "created"
  direction      :string  null: false          # inbound|outbound
  from_address   :string  null: false
  to_address     :string  null: false
  subject        :string
  message_id     :string                        # this email's Message-ID
  in_reply_to    :string                        # parent Message-ID (Strategy-2 threading)
  timestamps
  index [:record_id, :id]; index :creator_id
  index :message_id, unique: true               # nullable-unique: idempotent ingest (SNS redelivery)
  add_foreign_key :records
  add_foreign_key :users, column: :creator_id   # nullable FK
```
Reply body → Action Text (`has_rich_text :content`).

## Models

### `app/models/customer.rb`
```ruby
class Customer < ApplicationRecord
  has_many :licenses, dependent: :nullify   # licenses reference customer_id
  has_many :tickets,  dependent: :nullify

  normalizes :email, with: ->(e) { e.strip.downcase }
  validates :name, :email, presence: true
  validates :email, uniqueness: true
end
```

### `app/models/license.rb`
```ruby
class License < ApplicationRecord
  include Recordable
  belongs_to :customer

  enum :status, %w[ active suspended expired revoked ].index_by(&:itself), default: :active

  validates :license_key, :product, presence: true
  validate  :license_key_unique_among_current

  def mutable? = false   # every change is a version

  private
    def license_key_unique_among_current
      dupes = License.current.where(license_key: license_key).where.not(record_id: record_id)
      errors.add(:license_key, "is already in use") if dupes.exists?
    end
end
```
`License.current` = current versions of live records; add the same `current`
scope pattern `Publishable` uses (see `Recordable`/`Publishable`), or inline:
`where(id: Record.active.where(recordable_type: "License").select(:recordable_id))`.

### `app/models/ticket.rb`
```ruby
class Ticket < ApplicationRecord
  include Recordable
  belongs_to :customer
  has_rich_text :content              # the customer's opening email

  enum :status, %w[ open pending on_hold resolved closed ].index_by(&:itself), default: :open

  validates :title, presence: true
  def mutable? = false

  # Carry the opener body forward on action-only versions (status change, trash…).
  def build_successor(event:, creator:, **changes)
    super.tap { |v| v.content = content.body unless changes.key?(:content) }
  end

  # Live replies under this ticket — mirrors Record#comments.
  def replies
    Reply.where(id: record.children.active.where(recordable_type: "Reply").select(:recordable_id))
      .includes(:rich_text_content, :record).order(:record_id)
  end
end
```

### `app/models/reply.rb`
```ruby
class Reply < ApplicationRecord
  include Recordable
  belongs_to :creator, class_name: "User", optional: true   # inbound has no User
  has_rich_text :content

  enum :direction, %w[ inbound outbound ].index_by(&:itself)

  validates :direction, :from_address, :to_address, presence: true
  def mutable? = false

  def build_successor(event:, creator:, **changes)
    super.tap { |v| v.content = content.body unless changes.key?(:content) }
  end
end
```

### `app/models/record.rb` (edits)
```ruby
RECORDABLE_TYPES = %w[ Post Comment ChatLine Message License Ticket Reply ]

# scopes
scope :licenses, -> { where(recordable_type: "License") }
scope :tickets,  -> { where(recordable_type: "Ticket") }
scope :replies,  -> { where(recordable_type: "Reply") }

# reply-by-email routing token (tamper-proof, model-level, Rails 7.1+)
generates_token_for :ticket_reply       # no expiry: customers reply weeks later
```
Create Tickets and Replies with the existing `Record.originate(version, parent:)`
transaction (a Reply passes `parent: ticket.record`), same as `CommentsController`.

## Routing model — Message-ID threading (the 37signals / Help Scout pattern)

Verified against a real Basecamp support email (Help Scout): **no `Reply-To`,
no plus-addressing.** The reply target stays a clean `support@`, and the routing
key is **embedded in the `Message-ID` localpart** —
`<reply-23356-…nonces…@helpscout.net>` where `23356` is the conversation id.
Replies carry it back in `In-Reply-To`/`References` (standard RFC threading,
near-universally preserved by mail clients), and inbound parses it to thread.

We adopt the same shape, improved with a **cryptographic** token instead of an
opaque nonce: the Message-ID localpart carries a `generates_token_for` token so
it's tamper-proof, not just unguessable.

- Outbound Message-ID: `<reply-<ticket.record_id>-<token>@<domain>>`,
  token = `ticket.record.generate_token_for(:ticket_reply)`.
- Inbound: extract the token from `In-Reply-To`/`References`,
  `Record.find_by_token_for(:ticket_reply, token)`.
- `record_id` in the localpart is a human-readable convenience only; the **token
  is authoritative**.

## Outbound mail — `TicketMailer` (SES v2 send, per [[0008-email-relay-amazon-ses]])

Flow to send an agent reply: (1) build an **outbound Reply** version, (2)
`Record.originate(reply, parent: ticket.record)`, (3) set our token-bearing
Message-ID + threading headers, (4) deliver, (5) persist the Message-ID on the
Reply.

```ruby
class TicketMailer < ApplicationMailer
  def reply
    @ticket = params[:ticket]
    @reply  = params[:reply]
    token   = @ticket.record.generate_token_for(:ticket_reply)

    # Clean From/reply target (agent name as display) — no Reply-To, no plus-address.
    mail(to: @ticket.customer.email, subject: "Re: #{@ticket.title}") do |f|
      f.html { render "reply" }
    end

    # Token lives in OUR Message-ID; the customer's client echoes it into
    # In-Reply-To/References on reply → that's how we thread back.
    message.message_id = "reply-#{@ticket.record_id}-#{token}@#{ApplicationMailer.inbound_domain}"

    if (parent = @ticket.replies.where(direction: :inbound).last&.message_id)
      message.header["In-Reply-To"] = parent
      message.header["References"]  = parent
    end
  end
end
```
- `default from: "Covenant Support <support@#{inbound_domain}>"` on
  `ApplicationMailer` (override display name per agent if desired); tag with the
  **transactional** Configuration Set (ADR 0008).
- Deliver with `deliver_later`; persist `message.message_id` onto
  `@reply.message_id` so step-2 direct matching works later.
- Rich text body renders from `@reply.content` in the mailer view.

## Inbound mail — Action Mailbox `:amazon` ingress ([[0010-inbound-email-action-mailbox-ses]])

`config.action_mailbox.ingress = :amazon` (SES → SNS → the gem-provided route
`POST /rails/action_mailbox/amazon/inbound_emails`; SNS signature auth). This is
**new** — ADR 0008 covers *sending* only.

### Routing — `app/mailboxes/application_mailbox.rb`
```ruby
class ApplicationMailbox < ActionMailbox::Base
  routing(/^reply\+/i => :tickets)   # replies carrying a token
  routing(/^support@/i => :tickets)  # fresh mail → opens a new ticket
end
```

### Routing decision: the address, not the sender
The routing key is **which address the mail hit**, never the sender's email.
Routing by sender would be ambiguous the moment a customer has two open tickets
or raises a new topic (a reply and a new subject look identical). This is the
37signals pattern: `support@` is the public front door for *new* threads;
ongoing threads reply to the per-thread tokenized `reply+<token>@` address we
embed in every outbound `Reply-To`. The `From` address only resolves the
**Customer**. **Inbound precedence:**

1. **Token** in the recipient (`reply+<token>@`) → `Record.find_by_token_for` → that ticket.
2. else **`In-Reply-To`/`References`** matches a stored Reply/Ticket `Message-ID` → that ticket *(Strategy 2 — recovers token-stripped replies)*.
3. else → **new ticket** (Customer find-or-create by `From`).

Accepted trade-off: replying to an *old* notification to start a *new* topic
threads into the old ticket (agent splits it) — inherent to every token desk,
and far better than sender-email collapsing unrelated threads.

### `app/mailboxes/tickets_mailbox.rb`
```ruby
class TicketsMailbox < ApplicationMailbox
  def process
    return if already_ingested?                     # idempotent (SNS redelivery)

    record = locate_ticket_record                   # via token; nil if none/forged
    ticket = record&.recordable
    ticket ? append_reply(ticket) : open_ticket
  end

  private
    def already_ingested?
      id = mail.message_id
      id && (Reply.exists?(message_id: id) || Ticket.exists?(message_id: id))
    end

    def locate_ticket_record
      by_token || by_headers        # precedence: token, then In-Reply-To/References
    end

    def by_token
      token = mail.recipients.filter_map { |r| r[/^reply\+(.+)@/i, 1] }.first
      token && Record.find_by_token_for(:ticket_reply, token)
    end

    # Strategy 2 — recover replies whose client stripped the token.
    def by_headers
      ids = (Array(mail.in_reply_to) + Array(mail.references)).uniq
      return if ids.empty?
      Reply.where(message_id: ids).first&.record&.parent ||
        Ticket.where(message_id: ids).first&.record
    end

    def customer
      @customer ||= Customer.find_or_create_by(email: mail.from) do |c|
        c.name = Mail::Address.new(mail[:from].value).display_name || mail.from
      end
    end

    def append_reply(ticket)
      reply = Reply.new(direction: :inbound, from_address: mail.from,
        to_address: mail.to.to_a.join(", "), subject: mail.subject,
        message_id: mail.message_id, in_reply_to: mail.in_reply_to, creator: nil)
      reply.content = body_html
      Record.originate(reply, parent: ticket.record)   # threads under the ticket
    end

    def open_ticket
      ticket = Ticket.new(customer: customer, title: mail.subject.presence || "(no subject)",
        from_address: mail.from, message_id: mail.message_id, creator: Current.system_user)
      ticket.content = body_html
      Record.originate(ticket)
    end

    def body_html
      part = mail.html_part || mail.text_part || mail
      part.decoded
    end
end
```
- **`Current.system_user`** — inbound-opened tickets need a `creator` (Ticket's
  `creator_id` is NOT NULL). Add a seeded system `User` (e.g.
  `role: "system"`), or make `tickets.creator_id` nullable too. Decide in Open
  items; the sketch assumes a system user.
- **Attachments** → Active Storage on the Reply/Ticket (`mail.attachments`) —
  Phase 2, note in Open items.
- **Bounce** — optional `before_processing` guard (e.g. drop obvious spam with
  `bounce_with`); default policy is "unknown sender → new ticket", so no bounce.

### Token mechanism (why `generates_token_for`)
Defined on **`Record`** (stable id; the Ticket *version* id changes each edit).
Tamper-proof via `secret_key_base`, purpose-scoped (`:ticket_reply`), optional
expiry. Beats raw ids in the address (spoofable) and SGID string wrangling.
Strategy-2 (`Message-ID`/`In-Reply-To`) is stored per Reply as the fallback
match + ingest dedup.

## Controllers, routes, views

- `resources :customers`, `resources :licenses`, `resources :tickets`.
- Nested under a ticket: `resources :replies, only: %i[create]` (agent reply
  composer) — creates an **outbound Reply** and calls `TicketMailer`.
- Ticket **show** = the opener (`ticket.content`) + the `ticket.replies` thread
  (reuse the existing `.comment` block / thread markup), plus a reply composer
  (reuse `.composer`).
- Status controls (open/pending/closed) → a `revise(event: :updated, status:)`
  on the ticket record.
- Licenses index/show = plain CRUD scoped to `License.current`.

## Theme — Pine accent

Repoint the color tokens in `app/assets/stylesheets/01-tokens.css` (currently
Tailwind teal −15% chroma) to the **Pine** ramp. Pine = Teal's lightness/hue
with much lower chroma (greyer). Source of the ramp: the marketing site's
`assets/css/tokens.css` (`--color-pine-*`), reproduced here so this plan is
self-contained:

```
pine-50  oklch(98.4% 0     180.72)
pine-100 oklch(95.3% 0.003 180.801)
pine-200 oklch(91%   0.005 180.426)
pine-300 oklch(85.5% 0.012 181.071)
pine-400 oklch(77.7% 0.019 181.912)
pine-500 oklch(70.4% 0.034 182.503)
pine-600 oklch(60%   0.029 184.704)
pine-700 oklch(51.1% 0.029 186.391)
pine-800 oklch(43.7% 0.024 188.216)
pine-900 oklch(38.6% 0.019 188.416)
pine-950 oklch(27.7% 0.008 192.524)
```

Map covenant's brand tokens to Pine stops (keep the token *names* — components
never change):

| covenant token | today (teal −15%C) | → Pine stop |
|----------------|--------------------|-------------|
| `--brand-deep`   | teal-950 −15%C | `pine-950` |
| `--brand-strong` | teal-800 −15%C | `pine-800` (white-text fills; verify AA/AAA) |
| `--brand-muted`  | teal-700 −15%C | `pine-700` |
| `--brand`        | teal-500 −15%C | `pine-500` |
| `--accent-soft`  | teal-100 −15%C | `pine-100` |
| `--menu-context-bg` | teal-800-ish | `pine-800` |
| `--link` / `--brand-text` / `--ink-on-soft` | dark teal | `pine-800`/`pine-900` (contrast-tuned) |

`--accent` stays `var(--brand)`, so every component re-themes with **no
component edits**. Marketing's note applies: white button text needs the ~700
stop to clear WCAG AA on Pine's lighter ramp — **check contrast** (checklist).

## CSS (CUBE/BEM per [[css-architecture]])

- Prefer composing existing standard blocks. The ticket thread reuses
  `.comment` / `.list` / `.composer` wholesale; inbound vs outbound is a
  **modifier** (`.comment--inbound` / `.comment--outbound`), not a new block.
- Genuinely new blocks (one file each, `@layer components`, BEM header comment,
  demo at `/theme`): `.ticket` (header: title + status pill + customer),
  `.license` (license card/row), maybe `.status-pill`.
- Tokens only — no literal colors. New files sort alphabetically; cascade is by
  layer, so filenames are free.

## Config / environment

- **Gemfile:** `aws-sdk-rails` (SES v2 send **and** the `:amazon` Action Mailbox
  ingress) + `aws-sdk-sns` if not pulled transitively (SNS signature verify).
- **`config/environments/production.rb`:**
  - `config.action_mailbox.ingress = :amazon`
  - `config.action_mailer.delivery_method = :ses_v2` (+ region)
  - `config.action_mailer.default_url_options = { host: … }`
  - `config.action_mailbox.amazon.subscribed_topics = [<SNS topic ARNs>]`
- **Credentials:** SES region + IAM key/secret (shared with send), the inbound
  receiving domain, SNS topic ARN(s).
- **AWS/DNS (new vs ADR 0008, which is send-only):** an **SES inbound receipt
  rule** for the receiving domain (MX → SES inbound endpoint) publishing to an
  **SNS topic** subscribed to the ingress URL. Add this to
  [[ses-migration-runbook]] as an inbound section.
- Dev stays on `letter_opener`; exercise inbound with the Action Mailbox
  conductor (`/rails/conductor/action_mailbox/inbound_emails`).

## Testing

- **Mailbox** (`ActionMailbox::TestCase`): `receive_inbound_email_from_mail`
  for (a) reply with a valid token → appends a Reply to the right ticket; (b)
  forged/absent token → opens a new Ticket + Customer; (c) duplicate
  `Message-ID` → no second row (idempotent).
- **Mailer**: `TicketMailer#reply` sets `Reply-To: reply+<token>@…` and
  `In-Reply-To`; token round-trips through `Record.find_by_token_for`.
- **Models**: License/Ticket/Reply version on edit (`mutable? == false`);
  `Ticket#replies` returns current inbound+outbound in order; Reply allows a
  nil creator.

## Build checklist (phased)

- **A — Schema & models:** migrations 1–4; Customer/License/Ticket/Reply;
  `RECORDABLE_TYPES` + scopes + `generates_token_for` on Record; seed a system
  user (or make ticket creator nullable).
- **B — In-app UI:** routes/controllers/views for customers, licenses, tickets;
  ticket thread (reuse `.comment`) + reply composer; status controls.
- **C — Outbound:** `TicketMailer#reply`, token Reply-To, threading headers,
  store sent Message-ID; wire the composer to send.
- **D — Inbound:** Gemfile + production config; `ApplicationMailbox` routing;
  `TicketsMailbox` (locate, dedup, append/open, customer resolve); runbook
  inbound section (SES receipt rule → SNS).
- **E — Theme & CSS:** Pine token repoint (+ contrast check); `.ticket` /
  `.license` blocks; `/theme` demos.
- **F — Tests:** mailbox, mailer, model.

## Status — BUILT (2026-07-22)

Phases A–F are implemented and tested (SES/AWS integration deferred — the
mailbox/mailer code is in place and exercised via the Action Mailbox conductor;
production ingress config stays commented). See the [[log]] build entries. The
open items below were resolved at execution:

## Open items / assumptions — resolved

1. **Ticket status set** — **`open | pending | on_hold | resolved | closed`**
   (default `open`). Went with the fuller lifecycle: `on_hold` = blocked on
   us/a third party, `resolved` = fixed but not archived. `status` is a string
   column, so this was an enum-only change. The dashboard lists **open** tickets
   with links to the pending/on-hold queues; the index filters by any status.
2. **License status set** — `active | suspended | expired | revoked` (as planned).
3. **Inbound ticket creator** — **seeded `system` User** (`role: :system`,
   `User.system`), stamped on inbound tickets *and* replies. The spine's
   `records.creator_id` is NOT NULL, so a truly nil creator can never reach it —
   `Reply.creator` therefore stays **required** (via `Recordable`); the nullable
   `replies.creator_id` column is a latent affordance only. `User.people`
   (non-system) guards first-run Setup so the seed doesn't block it.
4. **License key uniqueness** — validation among `License.current` (as planned).
5. **Message-ID dedup** — a bare unique index was **wrong** (successor versions
   dup the row and repeat the id — the same trap as `license_key`). Shipped a
   **partial** unique index scoped to `event = 'created'` on both
   `tickets.message_id` and `replies.message_id`.
6. **Attachments** — still Phase 2 (not built).
7. **Inbound domain** — sourced from `ApplicationMailer.inbound_domain`
   (credentials/ENV, dev default `support.example.com`); finalize with the SES
   receipt rule.
8. **Agent-initiated tickets** — an in-app ticket's first message is its opener,
   same as an inbound email; no autoresponder (that's inbound-only).
9. **Autoresponder** — ~~`TicketMailer#acknowledgement` fires on inbound-opened
   tickets~~ **Removed 2026-07-22.** We never auto-reply to inbound mail: an
   opener is often spam or a spoofed From, and auto-replying is backscatter that
   harms sending reputation. Agents reply by hand. (Dropped the `acknowledgement`
   mailer, its views, and the `support_video_url` knob.)
