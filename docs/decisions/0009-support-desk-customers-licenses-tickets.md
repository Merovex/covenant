---
type: decision
title: Support desk — Customers, Licenses, Tickets, Replies
status: accepted
tags: [rails, data-model, record-recordable, licenses, tickets, support, customers]
created: 2026-07-22
updated: 2026-07-22
sources: [../support-desk-plan.md, 0006-record-recordable-generic-spine.md, 0007-versioned-recordables.md]
---

# 0009. Support desk — Customers, Licenses, Tickets, Replies

## Context
Covenant needs two customer-facing features: **License tracking** and **Ticket
management** (email in + out). It already has a versioned content spine
([[0006-record-recordable-generic-spine]], [[0007-versioned-recordables]]) —
`records` behind delegated-type recordables, immutable event-tagged versions,
`parent_id` threading — used today by Post, Message, Comment, ChatLine. It is
**single-tenant** (no `accounts`/`account_id`; identity is the `users` table).

We must associate both features with an external party (the "collector") who is
**not** a `User` and may never log in, and we want a full audit trail of license
and ticket changes without bespoke history tables. Full execution detail lives
in [[support-desk-plan]].

## Decision
Add four models, additively (nothing existing is removed):

- **`Customer`** — a **plain** table (like `Category`), not on the spine and not
  a `User`: `name`, `email` (unique), `company`, `notes`. The collector.
  `has_many :licenses, :tickets`. External parties stay cleanly separate from
  staff `users`.
- **`License`** — a **recordable** (`include Recordable`, not `Publishable`):
  `customer_id`, `license_key`, `product`, `seats`, `issued_at`, `expires_at`,
  `status` (active/suspended/expired/revoked). Structured, no rich text.
- **`Ticket`** — a **recordable** that is the *bucket* **and** holds the
  customer's opening email: `has_rich_text :content`, plus `customer_id`,
  `title`, `status` (open/pending/closed).
- **`Reply`** — a **recordable** for every message *after* the opener (inbound or
  outbound email): `has_rich_text :content`, `direction` (inbound/outbound),
  `from_address`, `to_address`, `subject`, `message_id`, `in_reply_to`. Its
  `record.parent_id` = the Ticket's record, so the thread reuses the existing
  spine threading (`Ticket#replies` mirrors `Record#comments`).

All three recordables are **immutable** (`mutable? = false`, like `Comment`):
every status change or email is a permanent version → free audit history.
`Reply.creator_id` is **nullable** (inbound customer mail has no `User` author);
Ticket/Reply carry the body forward on action-only versions via
`build_successor` (the `Comment` pattern). `RECORDABLE_TYPES` gains
`License`, `Ticket`, `Reply`.

## Consequences
- **No new history machinery** — versioning, trash/restore, and threading come
  free from the spine.
- **Customers are first-class but lightweight** — a plain table keeps external
  contacts out of `users` and out of the version cursor.
- **License key uniqueness** must be validated among **current** versions
  (`License.current`), not by a raw DB unique index (version rows repeat the key).
- **Inbound-opened tickets need a creator** — Ticket `creator_id` is NOT NULL;
  either seed a `system` User or make the column nullable (deferred to the plan's
  open items).
- **Email plumbing is a separate decision** — see
  [[0010-inbound-email-action-mailbox-ses]].

## Alternatives considered
- **Reuse `User` (role: customer)** — reuses email/auth plumbing but mixes
  external customers into the staff identity table; rejected for a muddier trust
  boundary.
- **Customer as a recordable** — versioned history for a contact record is
  overkill; a plain table is right.
- **Reuse/extend `Comment` for ticket emails** — would relax Comment's
  invariants (author-required, User-authored, instantly public) on a table shared
  by posts/messages/forum; a dedicated `Reply` keeps `comments` untouched.
- **Bespoke `ticket_events` history table** — duplicates what the spine already
  gives every recordable.

## Links
Related: [[support-desk-plan]] · [[0006-record-recordable-generic-spine]] ·
[[0007-versioned-recordables]] · [[0010-inbound-email-action-mailbox-ses]]
Supersedes: — · Superseded by: —
