# Overview — Covenant

> Living synthesis of the current state of the project. Update this whenever the
> shape of the work changes. Keep it short — details live in linked pages.

## What this is

Covenant — a Rails 8.x application (Ruby 4.0.5, app module `Covenant`). Scaffolded
from the **Alcovo** template, so older ADRs, design docs, and CSS still say
"Alcovo" — treat those as the same codebase. Covenant is a **single-tenant
support desk**: license tracking + ticket management (email in and out) built on
the Record/Recordable spine. This `docs/` folder is the single home for both
design/reference docs and the work log; see [[CLAUDE]] for how it's maintained.

## Current state (2026-07-22)

- **Renamed Alcovo → Covenant** across the app (module, views, mailer copy,
  Kamal deploy). ADRs and reference docs keep the historical name as-is.
- **Whole site behind authentication.** Root is now a **dashboard**, not the
  styleguide: new-license stat cards (today / this week / month / year) over the
  **open-ticket queue**, with links to the pending and on-hold queues. Only the
  session / setup / signup flows are public. Dev convenience: the "check your
  email" page surfaces the magic-link code (development only) with a one-click
  sign-in. A seeded non-interactive `system` user (`User.people` excludes it)
  authors email-ingested content without blocking first-run Setup.
- **Support desk shipped and LIVE** ([0009](decisions/0009-support-desk-customers-licenses-tickets.md),
  [0010](decisions/0010-inbound-email-action-mailbox-ses.md), [[support-desk-plan]]):
  `Customer` (plain table), `License` / `Ticket` / `Reply` (recordables on the
  spine, immutable → free audit history). Ticket opener + replies are Action
  Text; replies thread under the ticket via `records.parent_id`, mirroring
  `Record#comments`. Lifecycle: **open · pending · on_hold · resolved · closed**,
  now automated — agent reply → pending, customer reply → reopen, `resolved_at`
  + a daily job close resolved tickets after a week. Admin-only.
  - **Email is live on SES**, deployed to **`covenant.verkilo.com`** (reused the
    `merovex-press` AWS account; DKIM `d=verkilo.com`, DMARC pass). Inbound
    `support@`/`press@` → S3 → SNS → the `:ses` ingress → Tickets; outbound
    `TicketMailer` (agent replies + agent-opened openers, **no autoresponder**).
    Threading is anchored on the **SES-assigned Message-ID** (SES rewrites ours),
    captured on send. All outbound mail is **Verkilo-branded**. See [[ses-migration-runbook]].
  - **Desk UX**: quoted reply history folds into a collapsed `<details>`; the
    customer's other-tickets context panel; typeahead customer picker;
    "open & send to customer"; licensed-customer marker + filter; and a
    **staff-only rich-text `Notable` note** (un-versioned, on the Record for
    Ticket/License, on Customer directly — a dull-yellow sticky panel).
- **Theme repointed to Pine** (Teal's lightness/hue, chroma dropped ~75%).
- The generic template sections (Posts / Forum / Chatroom) are **hidden from
  nav** — their code remains, but Covenant presents purely as a support desk.
  See [[inactive-features]] for what's dormant and how to bring it back.

## Earlier state (2026-07-03) — the content spine

- Passwordless auth (magic links), first-run Setup, the design system.
- **Record/Recordable spine** ([0006](decisions/0006-record-recordable-generic-spine.md))
  + **versioned recordables** ([0007](decisions/0007-versioned-recordables.md)):
  tenant-agnostic `Record` envelope, immutable event-tagged versions behind a
  record-keyed identity (`/posts/:id` = Record id); drafts mutate, published
  content versions on every save; change feed + tracked-change diffs; scheduled
  publishing. `Post` / `Message` / `Comment` / `ChatLine` were the first
  recordables; `License` / `Ticket` / `Reply` now join them.

## Core vocabulary

Covenant is **single-tenant**: there is no `accounts` table and no `account_id`.
The real identity table is `users` (`email_address`, `name`, `role` —
`member` / `domain_admin` / `system`). The Person / User / Account vocabulary in
[[domain-vocabulary]] / [0002](decisions/0002-domain-vocabulary-person-user-account.md)
is notional and deferred; a host app that needs tenancy would add `Account` +
`records.account_id` as a spine extension.

## Key references

- [Reference & design docs](index.md#reference--design-docs) — data model, authentication, database & scaling, Lexxy/ActiveRecord, SES runbook, support-desk plan.
- [[inactive-features]] — template sections kept in the code but hidden from nav.
- Schema: [../db/schema.rb](../db/schema.rb).

## Open threads

- **DMARC still at `p=quarantine`** — softened for SES bring-up; tighten back to
  `p=reject` after a week+ of clean aggregate reports. The `verkilo.com →
  merovex.com` cross-domain `_report._dmarc` authz still needs adding (on
  merovex.com's Google DNS) for reports to actually arrive.
- **Inbound S3 objects are never deleted** — SES keeps every raw email in
  `covenant-inbound-email` forever (the app-side Action Mailbox copy self-expires
  ~30 days). Add an S3 lifecycle rule when convenient.
- **Dead `customers.notes` column** — the old plain-text notes were replaced by
  the rich `Notable` note; the column lingers unused (drop or migrate later).
- Dashboard open-ticket list is **unpaginated** (cap/paginate before it grows).
- `news.verkilo.com` marketing identity + tracking domain are **provisioned
  ahead** of any newsletter (no `AnnouncementMailer` yet).
