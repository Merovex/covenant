---
type: concept
title: SES/SNS setup runbook — Covenant (verkilo.com)
status: active
tags: [rails, email, ses, sns, aws, dns, runbook, action-mailbox]
created: 2026-07-10
updated: 2026-07-22
sources: [decisions/0008-email-relay-amazon-ses.md, decisions/0010-inbound-email-action-mailbox-ses.md]
---

# SES/SNS setup runbook — Covenant (verkilo.com)

> **✅ DONE / LIVE (2026-07-22).** SES is fully set up and deployed to
> `covenant.verkilo.com`. Outbound verified (magic-link DKIM `d=verkilo.com`,
> DMARC pass) and inbound verified (a real `support@verkilo.com` email opened a
> Ticket). This runbook is kept as the operational record + rebuild reference.
> Loose ends live in [[overview]] Open threads: DMARC is still `p=quarantine`
> (tighten to `reject` after clean reports), the `verkilo.com._report._dmarc`
> authz on **merovex.com's Google DNS** still needs adding, and an S3 lifecycle
> rule for `covenant-inbound-email` is optional hygiene. Two SES gotchas learned
> the hard way: the `:ses` ingress wants a **singular** `subscribed_topic`, and
> **SES rewrites the outbound Message-ID** (threading re-anchored on the
> SES-assigned id — see [[0010-inbound-email-action-mailbox-ses]] erratum).

Operational checklist for standing up Amazon SES for Covenant — **both**
directions: outbound send ([[0008-email-relay-amazon-ses]]) and inbound support
mail ([[0010-inbound-email-action-mailbox-ses]]). Most of this is AWS console +
Cloudflare DNS; the app code is already wired (see Status). Work top to bottom;
each step says how to verify it's green. Check boxes as you go — living doc.

> **Reusing an existing SES account.** The AWS account is already set up for a
> sibling app (out of the sandbox, IAM user, config sets, and an outbound-events
> SNS topic all exist). So the account-level, long-lead items (**IAM user**,
> **account suppression**, **production access / sandbox exit**) are **reuse +
> verify**, not create. The genuinely new work is: **verify the `verkilo.com`
> identities + DKIM**, their **MAIL FROM / DMARC DNS**, and the **entire inbound
> stack** (S3 bucket + receipt rule + MX + a dedicated inbound SNS topic). We
> still walk every step to confirm nothing was missed.

## Status

- **Inbound support desk: code DONE and on `master`** (ADR 0010). Gem
  `aws-actionmailbox-ses`, `ApplicationMailbox` → `TicketsMailbox`,
  `TicketMailer`, and `ApplicationMailer.inbound_domain`. Ingress stays **off**
  until `credentials[:support][:sns_topic_arn]` is set (guarded in
  `config/environments/production.rb`).
- **Outbound send: code wired this session.** Gem `aws-actionmailer-ses`;
  `:ses_v2` delivery + `ses_v2_settings` in `production.rb`, guarded by the
  `:ses` credentials; `default_url_options` host `verkilo.com` (override
  `APP_HOST`). Dormant until the `:ses` credentials exist.
- **Outbound bounce/complaint webhook: intentionally NOT built.** Covenant has no
  `Subscriber` model and doesn't track magic-link opens; **account-level
  suppression (Step 8, reused) is the net.** Revisit only if a newsletter stream
  lands. (The old Inkwell-copied runbook claimed a `Webhooks::SesController` /
  `POST /webhooks/ses` was "already built" — it never existed here.)
- **Marketing identity is provisioned ahead of need.** There is no
  `AnnouncementMailer` yet; `news.verkilo.com` is stood up so a future newsletter
  doesn't need a second DNS pass. Steps that are marketing-only are marked.
- **Phase 0 (this doc): the operator's remaining work** — AWS console + Cloudflare.

## Credentials to add (then deploy)

`bin/rails credentials:edit` (or set on the server). The app reads exactly these
keys; both blocks are optional and each stream stays dormant until its block
exists:

```yaml
ses:
  region: us-east-1
  access_key_id: <reused IAM key>            # existing sibling-app IAM user
  secret_access_key: <reused IAM secret>
  transactional_config_set: <existing config set>   # optional; omit = no config set
support:
  inbound_domain: verkilo.com                # From = support@verkilo.com; receive support@ + press@
  sns_topic_arn: arn:aws:sns:us-east-1:<acct>:covenant-inbound   # the NEW inbound topic (Step 7b)
```

Notes:
- **No `transactional_from`/`marketing_from` keys** — the app derives the support
  `From` as `support@#{inbound_domain}` (`ApplicationMailer`), and magic-links
  inherit that default. A dedicated `noreply@` isn't wired; add one only if you
  want auth mail to be unreplyable.
- Until `:ses` exists, prod delivery falls back to Rails' SMTP default (nothing
  sends); dev uses `letter_opener`. Until `:support[:sns_topic_arn]` exists, the
  Action Mailbox ingress stays off.

## Variables

**Two sending identities** so transactional and marketing sign with different DKIM
`d=` domains — a heavy announcement blast can't drag magic-links toward spam. See
[[0008-email-relay-amazon-ses]] / the reputation-isolation rationale.

| Key | Value | Notes |
|-----|-------|-------|
| Root domain | `verkilo.com` | org domain; DMARC published here covers subdomains |
| AWS region | `us-east-1` | **confirm** — MAIL FROM MX + inbound-SMTP targets are region-specific |
| **Transactional** identity | `verkilo.com` (apex) | magic-links + support; send `from: support@verkilo.com`, DKIM `d=verkilo.com` |
| **Marketing** identity | `news.verkilo.com` | announcements (provisioned ahead); `from: news@news.verkilo.com` |
| Transactional MAIL FROM | `bounce.verkilo.com` | SPF alignment for the auth/support stream |
| Marketing MAIL FROM | `bounce.news.verkilo.com` | SPF alignment for the news stream |
| Tracking (redirect) domain | `click.news.verkilo.com` | branded open/click links — **marketing only** |
| **Inbound** mailboxes | `support@verkilo.com`, `press@verkilo.com` | receive on the apex → SES receipt rule → S3 → SNS; both open Tickets today |
| Link host (email body URLs) | `verkilo.com` | `default_url_options[:host]` / `APP_HOST`; the app's web host |
| IAM user | **reused** (sibling app) | least-privilege send + inbound-bucket read; ADR 0008 Option A |
| Config sets | **reused** transactional set (marketing set for later) | picked per-message by the mailers |
| Outbound-events SNS topic | **reused** (sibling app) | only relevant if we later build an events webhook — skipped for now |
| Inbound SNS topic | `covenant-inbound` (**new**) | delivers receipt notifications to the `:ses` ingress |
| Inbound S3 bucket | `covenant-inbound-email` (**new**) | receipt rule stores the raw message; app reads it back |
| DMARC report inbox | `dmarc@merovex.com` | cross-domain → needs `_report._dmarc` authz on merovex.com (Step 4) |

Where you edit DNS: **Cloudflare** (`verkilo.com` zone; `merovex.com` zone for the DMARC report authz).

> **Reputation split in one line:** transactional signs `d=verkilo.com`,
> marketing signs `d=news.verkilo.com`; receivers score them separately, so an
> announcement blast can never sink the login email. Account suppression (Step 8)
> keeps the bulk stream from souring the shared *account* reputation too.

---

## Step 1 — IAM sending identity  ☐  ♻️ reuse
**Goal:** a least-privilege credential the app uses to call SES + read the inbound
bucket. **Reusing the sibling app's IAM user** (ADR 0008 Option A) — no new user.

1. Confirm the reused user's inline policy allows `ses:SendEmail` /
   `ses:SendRawEmail`. **Add** S3 read on the inbound bucket (Step 7a) so the
   `:ses` ingress can fetch stored messages:
   ```json
   { "Effect": "Allow", "Action": ["s3:GetObject"],
     "Resource": "arn:aws:s3:::covenant-inbound-email/*" }
   ```
2. Put the existing access key/secret into `credentials[:ses]` (above).

**Verify:** the key is in Covenant's credentials; policy covers SendEmail + the
inbound-bucket GetObject. (Tighten SES `Resource` to the two verified-identity
ARNs once Step 2 creates them.)

## Step 2 — Two domain identities + Easy DKIM  ☐  🆕
**Goal:** prove ownership and sign each stream with its **own** DKIM `d=` domain —
the reputation firewall between magic-links and announcements.

**2a. Transactional — `verkilo.com` (apex)**
1. SES → **Configuration → Identities → Create identity → Domain** → `verkilo.com`.
2. Enable **Easy DKIM**, key type **RSA 2048**.
3. Add the **3 CNAME** records SES shows (`<token>._domainkey.verkilo.com` → `<token>.dkim.amazonses.com`) in the Cloudflare `verkilo.com` zone.

**2b. Marketing — `news.verkilo.com`** (provisioned ahead)
1. Same flow → `news.verkilo.com`, Easy DKIM RSA 2048, add its **own 3 CNAMEs**.

(In Cloudflare, set these DKIM CNAMEs to **DNS only** / grey-cloud — do not proxy.)

**Verify:** **both** identities show **Verified** + DKIM **Successful** (minutes to a few hours).

## Step 3 — Custom MAIL FROM subdomain per identity (SPF alignment)  ☐  🆕
**Goal:** SPF passes and *aligns* for DMARC on each stream (return-path lives under
the same brand, not `amazonses.com`).

**3a. On `verkilo.com`** → MAIL FROM `bounce.verkilo.com`
   - **MX**: `bounce.verkilo.com` → `feedback-smtp.us-east-1.amazonses.com` (priority 10)
   - **TXT (SPF)**: `bounce.verkilo.com` → `"v=spf1 include:amazonses.com ~all"`

**3b. On `news.verkilo.com`** → MAIL FROM `bounce.news.verkilo.com`
   - **MX**: `bounce.news.verkilo.com` → `feedback-smtp.us-east-1.amazonses.com` (priority 10)
   - **TXT (SPF)**: `bounce.news.verkilo.com` → `"v=spf1 include:amazonses.com ~all"`

> **Apex-MX caution:** the transactional MAIL FROM MX is on `bounce.verkilo.com`,
> a subdomain — it does **not** touch the apex MX. But **inbound** (Step 7) puts
> an MX on the apex `verkilo.com` itself. There is only one apex MX, so confirm
> `verkilo.com` isn't already receiving mail elsewhere (Workspace, etc.) before
> Step 7, or move inbound to a `support.verkilo.com` subdomain.

Leave the on-failure behavior as **"Use amazonses.com as fallback"** until each verifies.

**Verify:** MAIL FROM shows **Verified** on both identities.

## Step 4 — DMARC  ☐  🆕
**Goal:** publish a DMARC policy (monitor first, tighten later).

Aggregate reports go to `dmarc@merovex.com` (a **different domain** than the DMARC
record), so `merovex.com` must authorize the cross-domain reporting.

1. **DMARC record — on `verkilo.com`** (org-level → covers `news.`).
   Cloudflare `verkilo.com` zone → TXT, Name `_dmarc`:
   ```
   v=DMARC1; p=none; rua=mailto:dmarc@merovex.com; fo=1
   ```
2. **Cross-domain authorization — on `merovex.com`.** Cloudflare `merovex.com`
   zone → TXT, Name `verkilo.com._report._dmarc`
   (→ `verkilo.com._report._dmarc.merovex.com`):
   ```
   v=DMARC1;
   ```
   Without it the reports silently go nowhere.
3. **Mailbox:** ensure `dmarc@merovex.com` actually receives mail.
4. Keep `p=none` until a week+ of clean aggregate reports, then move to `quarantine`/`reject`.

**Verify** (Arch: `dig` needs `sudo pacman -S bind`; or `drill`/`resolvectl`):
```
dig +short TXT _dmarc.verkilo.com
dig +short TXT verkilo.com._report._dmarc.merovex.com
```

## Step 5 — Custom open/click tracking domain (marketing only)  ☐  🆕 · marketing
**Goal:** branded redirect links (`click.news.verkilo.com`) instead of `*.awstrack.me`. **Announcement stream only** — the auth/support stream is never tracked. Defer until a newsletter exists.

1. SES → on the marketing config set, **Tracking options → Use a custom redirect domain** → `click.news.verkilo.com`.
2. Add the region-specific **CNAME** SES gives (DNS only) in the `verkilo.com` zone.
3. Provide an ACM cert for HTTPS tracking links when prompted (prefer HTTPS).

**Verify:** tracking domain shows **Verified/Active** on the marketing config set.

## Step 6 — Configuration sets  ☐  ♻️ reuse
**Goal:** transactional is untracked; marketing (later) is tracked. Config sets
aren't bound to an identity — the mailer picks the set **per message**.

| Stream | Mailer / From | Config set |
|---|---|---|
| Transactional (`SessionMailer`, `TicketMailer`) | `support@verkilo.com` | reused transactional set → `credentials[:ses][:transactional_config_set]` |
| Marketing (`AnnouncementMailer`, later) | `news@news.verkilo.com` | reused/created marketing set → per-mailer `delivery_method_options` |

- **Reuse** the sibling app's **transactional** config set (or create
  `covenant-transactional` if you'd rather isolate event streams). It must **omit
  Open/Click** so SES won't inject the pixel or rewrite links on magic-link mail.
  Since we build no events webhook, the config set is optional for sending —
  leaving `transactional_config_set` unset is fine; bounces/complaints still hit
  account suppression.
- The **marketing** set (tracking + SNS events) is provisioned for later; wire it
  when `AnnouncementMailer` lands.

**Verify:** the transactional set (if used) exists and lists no Open/Click.

## Step 7 — Inbound: S3 + receipt rule + MX + SNS  ☐  🆕
**Goal:** mail to `support@verkilo.com` reaches Action Mailbox
(`POST /rails/action_mailbox/ses/inbound_emails`, the `:ses` ingress from the
`aws-actionmailbox-ses` gem). This whole step is **new** — the sibling app's
outbound topic is not reusable here.

**7a. S3 bucket** — create `covenant-inbound-email` (same region). Add a bucket
policy allowing SES to `s3:PutObject` (SES console provides the exact policy when
you add the S3 action). The IAM user reads it back (Step 1).

**7b. Inbound SNS topic** — SNS → **Create topic** (Standard) `covenant-inbound`.
Create an **HTTPS subscription** → endpoint
`https://verkilo.com/rails/action_mailbox/ses/inbound_emails`. The gem's ingress
auto-confirms the `SubscriptionConfirmation` handshake once
`credentials[:support][:sns_topic_arn]` is set and deployed. Put this topic ARN
in credentials.

**7c. MX on the receiving domain** — Cloudflare `verkilo.com` zone → **MX**,
Name `@` (apex), value `inbound-smtp.us-east-1.amazonses.com`, priority 10.
(See the Step 3 apex-MX caution — apex MX captures **all** `@verkilo.com` mail.)

**7d. SES receipt rule** — SES → **Email receiving → Rule sets → Create rule**:
recipient conditions `support@verkilo.com` **and** `press@verkilo.com` (the only
two accepted localparts — **no catch-all**, so SES silently drops mail to any
other address, killing most scraped/dictionary spam); actions **(1) S3** →
`covenant-inbound-email`, **(2) SNS** → `covenant-inbound`. Keep **spam+virus
scanning enabled** (default) so SES stamps `X-SES-Spam-Verdict` /
`X-SES-Virus-Verdict` on the message. Enable the rule set.

> **Routing:** `ApplicationMailbox` currently routes `all: :tickets`, so **both**
> `support@` and `press@` open Tickets today. Split `press@` into a dedicated
> `PressMailbox` (add a `routing /press@/i => :press` line) only when press needs
> different handling. There is **no autoresponder** — we never auto-reply to
> inbound mail (backscatter risk); agents reply by hand.

**Verify:** subscription state **Confirmed**; a test mail to `support@verkilo.com`
lands an `ActionMailbox::InboundEmail` and opens a Ticket (see Go-live).

## Step 8 — Account-level suppression (the net)  ☐  ♻️ reuse
**Goal:** SES auto-suppresses hard bounces/complaints so we never re-send. This is
Covenant's **primary** suppression (no `Subscriber` model), not just redundancy.

1. SES → **Configuration → Suppression list** → confirm account-level suppression
   is on for **Bounces and Complaints** (already enabled on the reused account).

**Verify:** suppression reasons show Bounce + Complaint enabled.

## Step 9 — Production access (sandbox exit)  ☐  ♻️ reuse
**Goal:** be out of the sandbox (200/day + verified-recipients-only).

The reused account is **already out of the sandbox** — nothing to request. Just
confirm and note the sending quota.

**Verify:** SES **Account dashboard** shows **Production access: Enabled**.

---

## Phase 0 done when…
- [ ] `:ses` + `:support` credentials added and deployed (see top)
- [ ] IAM key reused; policy covers SendEmail + inbound-bucket GetObject (Step 1)
- [ ] **Both** identities (`verkilo.com` + `news.`) **Verified**, DKIM **Successful** (Step 2)
- [ ] MAIL FROM **Verified** on both (Step 3); DMARC published (Step 4)
- [ ] Transactional config set decided (reuse / create / none) (Step 6)
- [ ] Inbound S3 bucket + receipt rule + apex MX + `covenant-inbound` topic; subscription **Confirmed** (Step 7)
- [ ] Account suppression confirmed on (Step 8); production access confirmed (Step 9)
- [ ] *(deferred, marketing)* tracking domain (Step 5), marketing config set (Step 6)

## Go-live check (Phase 3)
1. **Outbound:** trigger a magic-link sign-in; confirm it arrives and DKIM `d=` is
   `verkilo.com` (Gmail "Show original"). Watch SES guardrails (<5% bounce,
   <0.1% complaint).
2. **Inbound:** send a fresh email to `support@verkilo.com`; confirm a Ticket
   opens (no autoresponse — that's expected). Send one to `press@verkilo.com` and
   confirm it also opens a Ticket. Reply to a `TicketMailer` message and confirm
   it threads back onto the same ticket (the `Message-ID` token path, ADR 0010).
3. Tail logs: `kamal logs | grep -iE 'SES|ActionMailbox|InboundEmail'`.

## Links
Decisions: [[0008-email-relay-amazon-ses]] (send) · [[0010-inbound-email-action-mailbox-ses]] (receive) · [[0009-support-desk-customers-licenses-tickets]] (the ticket spine)
