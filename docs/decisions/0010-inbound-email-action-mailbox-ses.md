---
type: decision
title: Inbound support email — Action Mailbox (SES/SNS) + Message-ID token routing
status: accepted
tags: [rails, email, action-mailbox, action-mailer, ses, sns, tickets, routing]
created: 2026-07-22
updated: 2026-07-22
sources: [../support-desk-plan.md, 0008-email-relay-amazon-ses.md, ../ses-migration-runbook.md]
---

# 0010. Inbound support email — Action Mailbox (SES/SNS) + Message-ID token routing

> **Erratum (2026-07-22).** This ADR names the `:amazon` ingress
> (`config.action_mailbox.amazon.subscribed_topics`, route
> `/rails/action_mailbox/amazon/inbound_emails`) — that's the ingress built into
> the old monolithic `aws-sdk-rails`. Covenant uses the standalone
> **`aws-actionmailbox-ses`** gem, whose ingress is **`:ses`**
> (`config.action_mailbox.ses.subscribed_topic` — **singular**, one ARN, not the
> plural array; route `/rails/action_mailbox/ses/inbound_emails`). The decision
> is unchanged; only the identifiers differ. See [[ses-migration-runbook]].
>
> **Erratum 2 (2026-07-22) — the routing anchor changed.** This ADR routes on a
> signed token embedded in our **outbound `Message-ID`**. That does not survive
> Amazon SES: **SES overwrites the Message-ID** of every message it sends with
> its own `…@email.amazonses.com` id (proven in the field — a customer reply's
> `In-Reply-To` was the SES id, not our `reply-<id>-<token>`). So the token
> scheme never reaches the customer. **Fix:** we no longer set our own
> Message-ID; `Tickets::RepliesController` sends the reply with `deliver_now` and
> stores the **SES-assigned** Message-ID on the `Reply`. The customer's client
> echoes that id in `In-Reply-To`, and `TicketsMailbox` matches it back (the
> existing header-matching path). Threading is now anchored on the SES id, not a
> token; sender-email still resolves the `Customer` only, and a missing/dropped
> reference still degrades to a new ticket — never a misroute.

## Context
Tickets ([[0009-support-desk-customers-licenses-tickets]]) are email in **and**
out. [[0008-email-relay-amazon-ses]] committed to SES v2 for **sending only** —
there is no inbound path. We need to receive customer email, attach each message
to the right `Ticket`, and open a new one when there's no match.

The hard part is routing: an inbound reply is just a new email, and the sender's
address identifies the **person**, not the **conversation** (one customer → many
tickets). Routing by sender email is therefore ambiguous the moment a customer
has two open tickets or raises a new topic. A real Basecamp support email (Help
Scout) shows the industry answer: a clean `support@` reply target with the
routing key **embedded in the `Message-ID`** (`<reply-<conversationId>-…@…>`),
echoed back by the client in `In-Reply-To`/`References` on reply.

## Decision
**Receive via Action Mailbox with the Amazon `:amazon` ingress** (SES receipt
rule → SNS → `POST /rails/action_mailbox/amazon/inbound_emails`, SNS-signature
authenticated), and **route by a signed token carried in our outbound
`Message-ID`.**

- **Token:** Rails `generates_token_for :ticket_reply` defined on **`Record`**
  (the stable id; the Ticket *version* id changes each edit). Tamper-proof via
  `secret_key_base`, purpose-scoped — stronger than Help Scout's opaque nonce.
- **Outbound (`TicketMailer`):** clean `From: Support <support@domain>` (no
  `Reply-To`, no plus-addressing); set
  `Message-ID: <reply-<record_id>-<token>@domain>`. Persist it on the Reply.
- **Inbound (`TicketsMailbox`) precedence:**
  1. token parsed from `In-Reply-To`/`References` → `Record.find_by_token_for` → ticket;
  2. direct `Message-ID` match against stored Reply/Ticket rows (fallback);
  3. else → **new Ticket**, Customer find-or-create by `From`.
- **Sender email resolves the `Customer` only**, never the ticket.
- **Idempotent ingest:** dedup on `Message-ID` (nullable-unique) — SNS may
  redeliver.

## Consequences
- **Clean public mailbox** (`support@`) and standard RFC threading; no ugly
  plus-addresses, no reliance on custom headers surviving.
- **Extends 0008, doesn't replace it** — send path unchanged; adds an inbound
  **SES receipt rule + MX + SNS topic** for the receiving domain. Add an inbound
  section to [[ses-migration-runbook]] (0008's runbook is send-only).
- **Config:** `config.action_mailbox.ingress = :amazon`;
  `config.action_mailbox.amazon.subscribed_topics = [...]`; `aws-sdk-rails`
  (+ `aws-sdk-sns`). Dev uses the Action Mailbox conductor, not real SES.
- **Accepted trade-off:** replying to an *old* notification to start a *new*
  topic threads into the old ticket (agent splits it) — inherent to every token
  desk, and far better than sender-email collapsing unrelated threads.
- **Token-stripping clients** are covered by the direct Message-ID fallback;
  worst case degrades to a new ticket, never a misroute.

## Alternatives considered
- **Plus-addressed `Reply-To` (`reply+<token>@`)** — robust and easy to parse,
  but changes the visible reply address and needs the MX to accept arbitrary
  localparts; kept only as an optional secondary. The Message-ID model matches
  the proven 37signals/Help Scout behavior with a cleaner address.
- **Route by sender email** — ambiguous with multiple tickets per customer;
  rejected (this is the core reason a per-thread token exists).
- **SNS → HTTPS webhook we parse ourselves** (as 0008 does for events) — Action
  Mailbox's `:amazon` ingress already does inbound receipt + parsing + the
  InboundEmail lifecycle; no reason to hand-roll.
- **A third-party desk (Help Scout/Zendesk)** — the specimen that taught us the
  pattern, but we're building in-app on the existing spine; no integration.

## Links
Related: [[support-desk-plan]] · [[0009-support-desk-customers-licenses-tickets]] ·
[[0008-email-relay-amazon-ses]] · [[ses-migration-runbook]]
Supersedes: — · Superseded by: —
