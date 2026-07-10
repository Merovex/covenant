---
type: decision
title: Email relay — adopt Amazon SES/SNS
status: accepted
tags: [rails, email, ses, sns, aws, deliverability]
created: 2026-07-10
updated: 2026-07-10
sources: [../ses-migration-runbook.md]
---

# 0008. Email relay — adopt Amazon SES/SNS

## Context
Alcovo sends **only transactional mail today** — `SessionMailer` magic-links for
passwordless auth. Production mail is **unconfigured** (`smtp_settings` commented
out in `config/environments/production.rb`; development uses `letter_opener`), so
this is a **greenfield adoption**, not a migration off an existing relay.

We need a real sending path before auth email can go out in production. Forces:

- **Cost** — SES is ~$0.10/1k emails with no monthly minimum, which fits a
  low-volume magic-link stream with no floor to pay.
- **Deliverability of magic-links** — auth mail must land in the inbox; SES gives
  us DKIM/SPF/DMARC alignment and bounce/complaint signal to protect reputation.
- **Room to grow** — Alcovo may later add a newsletter/broadcast stream. Picking a
  relay whose Configuration Sets + message tags already support marketing keeps
  that door open without a second migration.

Constraint: Alcovo is **self-hosted (Kamal, not on AWS)**, so SES (send) and SNS
(events) are external APIs — no in-AWS infrastructure to operate.

## Decision
**Adopt Amazon SES v2 (send) + SNS (events)** as the email relay, using the same
architecture proven in the sibling Inkwell app (its ADR 0015).

- **Send path:** Action Mailer `:ses_v2` via `aws-sdk-rails` (SES API v2, not
  SMTP) — native Configuration Set + message-tag support, cleaner credentials.
- **Two sending identities / reputation firewall:** a **transactional** identity
  (magic-links) and a **marketing** identity, each signing with its own DKIM `d=`
  domain so a future newsletter run can never drag auth mail toward spam. The
  marketing identity is **provisioned ahead of need** — Alcovo has no
  `Subscriber`/`Broadcast` models yet; only the transactional stream is wired in
  the near term (see open dependency below).
- **Configuration Sets:** `*-transactional` (bounce/complaint only — we don't
  track magic-link opens) and `*-marketing` (open+click ON, branded tracking
  domain) for when the newsletter stream lands.
- **Event ingest:** **SNS → HTTPS webhook** (`POST /webhooks/ses`), authenticated
  by SNS signature (`Aws::SNS::MessageVerifier`); the controller auto-confirms the
  `SubscriptionConfirmation` handshake. No new AWS infra on the Kamal box.
- **Suppression:** **SES account-level suppression** for hard bounces/complaints as
  the immediate net. If/when an app-side `Subscriber` model exists it becomes the
  source of truth, with SES suppression as redundancy (mirrors Inkwell's 0011
  consent-trail split — not yet applicable to Alcovo).

**Rollout is phased; the AWS/DNS prerequisites gate everything** — captured
operationally in the [[ses-migration-runbook]] (Phase 0):

- **Phase 0 — AWS/DNS (no app code):** IAM least-privilege user; verify sending
  domain(s) + Easy DKIM; custom MAIL FROM subdomain (MX + SPF); DMARC (`p=none`
  to start); tracking domain (marketing only); Configuration Sets + SNS event
  publishing; SNS topic + HTTPS subscription; account suppression; **request
  production access (sandbox exit)** — ~24h lead, AWS wants bounce/complaint
  handling deployed first.
- **Phase 1 — Sending:** add `aws-sdk-rails`; `production.rb` → `:ses_v2` +
  region/creds + `default_url_options` host; `ApplicationMailer` default `from:`;
  tag `SessionMailer` with the transactional Configuration Set.
- **Phase 2 — Ingest:** `Webhooks::SesController` (SNS confirm + signature + event
  parse); `post "webhooks/ses"`.
- **Phase 3 — Go live:** validate in the SES sandbox (verified recipients); enable
  in prod once production access + DNS are green; watch SES guardrails (<5%
  bounce, <0.1% complaint).

## Consequences
- Alcovo gets a production-ready transactional email path with inbox-grade
  alignment (DKIM/SPF/DMARC) and bounce/complaint handling.
- **Marketing pieces are aspirational:** the runbook (copied verbatim from
  Inkwell) describes a marketing identity, tracking domain, `SubscriberMailer`/
  `PostBroadcastMailer`, and a consent log Alcovo **does not have**. Treat those
  steps as provisioning-ahead / reference until a newsletter ADR exists. **Open
  dependency:** a subscribers/consent decision (Inkwell's 0011) has no Alcovo
  equivalent — the runbook's `[[0011-subscribers-and-consent-log]]` link is an
  Inkwell reference and dangles here by design.
- **Naming:** the runbook keeps Inkwell's identifiers (`inkwell-ses`,
  `inkwell-marketing`/`-transactional`, `merovex.press`). Rename to Alcovo's own
  IAM user / Configuration Set / domain values at execution time.
- **Deployment config (not in the app):** provide `credentials[:ses]` (region,
  IAM key/secret, from, host, config-set names) and the SNS webhook path; complete
  Phase-0 DNS records; keep dev on `letter_opener`.
- **Production-access lead time is the schedule risk** — file the request early.

## Alternatives considered
- **SMTP relay (Postmark/Mailgun/generic SMTP)** — simplest Action Mailer wiring,
  but a monthly floor and no ownership of the event pipeline; SES's cost model and
  Configuration Set/tag machinery fit better and leave room for marketing.
- **SES SMTP interface** instead of API v2 — minimal code, but config-sets/tags go
  through clunky headers and credentials are a second secret; API v2 is the
  cleaner fit for tag-based event mapping.
- **Defer email entirely / keep `letter_opener`** — a non-option once auth email
  must ship to real users in production.

## Links
Related: [[ses-migration-runbook]] (Phase-0 ops checklist) · Based on: Inkwell ADR 0015 (Mailgun → SES migration)
Supersedes: — · Superseded by: —
