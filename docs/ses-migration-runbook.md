---
type: concept
title: SES/SNS setup runbook — Phase 0 (AWS + DNS)
status: active
tags: [rails, email, ses, sns, aws, dns, runbook]
created: 2026-07-10
updated: 2026-07-13
sources: [decisions/0008-email-relay-amazon-ses.md]
---

# SES/SNS setup runbook — Phase 0 (AWS + DNS)

Operational checklist for the **prerequisite** AWS/DNS work behind
[[0008-email-relay-amazon-ses]]. Phase 0 is all console + DNS — **no app
code**. Work top to bottom; each step says how to verify it's green before the
next. Check boxes as you go; this is a living doc.

> **Greenfield, not a migration:** Cohwall has never sent production mail, so
> there is no relay to cut over from — Phase 0 just stands up SES cleanly. The
> long-lead items are DNS propagation and the sandbox-exit approval (~24h); file
> those early. One step (SNS subscription, 7) needs the Phase-2 webhook endpoint
> live to confirm — that endpoint (`Webhooks::SesController`) is **already built
> and deployed**, so Step 7 can confirm immediately.

## Status

- **Phase 1 (sending) + Phase 2 (ingest): code is DONE and on `master`.** Gems
  (`aws-sdk-rails`, `aws-actionmailer-ses`, `aws-sdk-sns`), `:ses_v2` delivery in
  `config/environments/production.rb`, per-stream mailers
  (`SessionMailer` → transactional, `AnnouncementMailer` → marketing), and
  `POST /webhooks/ses`. It stays dormant until the `ses:` credentials below are
  present **and** Phase 0 is green.
- **Phase 0 (this doc): the operator's remaining work** — AWS console + Cloudflare.
- **Marketing ingest is a stub:** Cohwall has no `Subscriber`/`BroadcastDelivery`
  model, so `Webhooks::SesController#ingest` only logs bounce/complaint signal;
  SES account-level suppression (Step 8) is the actual "never re-send" net. The
  marketing identity/config set/tracking domain are provisioned **ahead of need**.

## Credentials to add (after Step 1 + Steps 2/6 name things)

`bin/rails credentials:edit` (or set on the server), then deploy:

```yaml
ses:
  region: us-east-1
  access_key_id: <cohwall-ses access key>
  secret_access_key: <cohwall-ses secret>
  host: cohwall.com                       # link host in email bodies
  transactional_from: noreply@mail.cohwall.com
  marketing_from: news@news.cohwall.com
  transactional_config_set: cohwall-transactional
  marketing_config_set: cohwall-marketing
```

Until `ses:` exists, the mailers fall back to `noreply@example.com` and no
config set — harmless in dev (`letter_opener`), but production won't send.

## Variables

**Two sending identities** so transactional and marketing sign with different DKIM
`d=` domains — a heavy announcement blast can't drag magic-links toward spam. See
[[0008-email-relay-amazon-ses]] / the reputation-isolation rationale.

| Key | Value | Notes |
|-----|-------|-------|
| Root domain | `cohwall.com` | org domain; DMARC published here covers all subdomains |
| AWS region | `us-east-1` | **confirm** — MAIL FROM MX + tracking CNAME targets are region-specific |
| **Transactional** identity | `mail.cohwall.com` | magic-links; send `from: noreply@mail.cohwall.com` |
| **Marketing** identity | `news.cohwall.com` | announcements; send `from: news@news.cohwall.com` |
| Transactional MAIL FROM | `bounce.mail.cohwall.com` | SPF alignment for the auth stream |
| Marketing MAIL FROM | `bounce.news.cohwall.com` | SPF alignment for the news stream |
| Tracking (redirect) domain | `click.news.cohwall.com` | branded open/click links — **marketing only** |
| Link host (email body URLs) | `cohwall.com` | `default_url_options[:host]`; independent of the sending identity |
| SNS webhook URL | `https://cohwall.com/webhooks/ses` | endpoint live (Phase 2, `Webhooks::SesController`) |
| DMARC report inbox | `dmarc@merovex.com` | cross-domain → needs the `_report._dmarc` authz record on merovex.com (Step 4) |
| IAM user | `cohwall-ses` | dedicated least-privilege user in the shared AWS account (ADR 0008, Option A) |
| Config sets | `cohwall-transactional` / `cohwall-marketing` | picked per-message by the mailers |
| SNS topic | `cohwall-ses-events` | both config sets publish here |

Where you edit DNS: **Cloudflare** (`cohwall.com` zone; `merovex.com` zone for the DMARC report authz).

> **Reputation split in one line:** transactional signs `d=mail.cohwall.com`,
> marketing signs `d=news.cohwall.com`; receivers score them separately, so an
> announcement blast can never sink the login email. Config sets and suppression
> (below) keep the bulk stream from souring the shared *account* reputation too.

---

## Step 1 — IAM sending identity  ☐
**Goal:** a least-privilege credential the app uses to call SES (nothing else).
Dedicated `cohwall-ses` user in the shared AWS account (ADR 0008, Option A) so a
leak on the demo box never forces rotating inkwell's key.

1. IAM → **Users** → Create user `cohwall-ses` (no console access, programmatic only).
   The wizard's permissions step has **no inline-policy option** — pick **Attach
   policies directly**, select nothing, and finish.
2. Open the created user → **Permissions** tab → **Add permissions ▾ → Create
   inline policy → JSON** → paste, name it `cohwall-ses-send`, create:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": ["ses:SendEmail", "ses:SendRawEmail"],
       "Resource": "*"
     }]
   }
   ```
   (Tighten `Resource` to the two verified-identity ARNs once Step 2 creates them,
   so this key can send only as `mail.cohwall.com` / `news.cohwall.com`.)
3. On the user → **Security credentials → Create access key** → **Application
   running outside AWS** → save the **Access key ID** + **Secret**. This is the
   only time the secret is shown → goes into `ses.access_key_id` / `ses.secret_access_key`.

**Verify:** user exists with the inline policy; key pair saved somewhere safe (password manager, not the repo).

## Step 2 — Two domain identities + Easy DKIM  ☐
**Goal:** prove ownership and sign each stream with its **own** DKIM `d=` domain —
this is the reputation firewall between magic-links and announcements.

Do this **twice**, once per identity:

**2a. Transactional — `mail.cohwall.com`**
1. SES → **Configuration → Identities → Create identity → Domain** → `mail.cohwall.com`.
2. Enable **Easy DKIM**, key type **RSA 2048**.
3. Add the **3 CNAME** records SES shows (`<token>._domainkey.mail.cohwall.com` → `<token>.dkim.amazonses.com`) in the Cloudflare `cohwall.com` zone.

**2b. Marketing — `news.cohwall.com`**
1. Same flow → `news.cohwall.com`, Easy DKIM RSA 2048, add its **own 3 CNAMEs**.

(In Cloudflare, set these DKIM CNAMEs to **DNS only** / grey-cloud — do not proxy them.)

**Verify:** **both** identities show **Verified** + DKIM **Successful** (minutes to a few hours). Don't request production access until both are green.

## Step 3 — Custom MAIL FROM subdomain per identity (SPF alignment)  ☐
**Goal:** SPF passes and *aligns* for DMARC on each stream (return-path lives under
the same brand, not `amazonses.com`).

Do this on **each** identity:

**3a. On `mail.cohwall.com`** → MAIL FROM `bounce.mail.cohwall.com`
   - **MX**: `bounce.mail.cohwall.com` → `feedback-smtp.us-east-1.amazonses.com` (priority 10)
   - **TXT (SPF)**: `bounce.mail.cohwall.com` → `"v=spf1 include:amazonses.com ~all"`

**3b. On `news.cohwall.com`** → MAIL FROM `bounce.news.cohwall.com`
   - **MX**: `bounce.news.cohwall.com` → `feedback-smtp.us-east-1.amazonses.com` (priority 10)
   - **TXT (SPF)**: `bounce.news.cohwall.com` → `"v=spf1 include:amazonses.com ~all"`

Leave the on-failure behavior as **"Use amazonses.com as fallback"** until each verifies.

**Verify:** MAIL FROM shows **Verified** on both identities.

## Step 4 — DMARC  ☐
**Goal:** publish a DMARC policy (monitor first, tighten later).

Aggregate reports go to `dmarc@merovex.com` (a **different domain** than the
DMARC record), so `merovex.com` must authorize the cross-domain reporting — else
mailbox providers won't send the reports.

1. **DMARC record — on `cohwall.com`** (org-level → covers `mail.` and `news.`).
   Cloudflare `cohwall.com` zone → TXT, Name `_dmarc`:
   ```
   v=DMARC1; p=none; rua=mailto:dmarc@merovex.com; fo=1
   ```
2. **Cross-domain authorization — on `merovex.com`.** Cloudflare `merovex.com`
   zone → TXT, Name `cohwall.com._report._dmarc`
   (→ `cohwall.com._report._dmarc.merovex.com`):
   ```
   v=DMARC1;
   ```
   This is `merovex.com` saying "I accept DMARC reports for `cohwall.com`."
   Without it the reports silently go nowhere.
3. **Mailbox:** ensure `dmarc@merovex.com` actually receives mail (real mailbox or
   catch-all with working MX on `merovex.com`), or the reports land nowhere.
4. Keep `p=none` through cutover; move to `quarantine`/`reject` only after a week+
   of clean aggregate reports.

**Verify** (Arch: `dig` needs `sudo pacman -S bind`; or use `drill`/`resolvectl`):
```
dig +short TXT _dmarc.cohwall.com
dig +short TXT cohwall.com._report._dmarc.merovex.com
```
Both should return their `v=DMARC1...` values.

## Step 5 — Custom open/click tracking domain (marketing only)  ☐
**Goal:** branded redirect links (`click.news.cohwall.com`) instead of `*.awstrack.me` — better trust/deliverability. **Announcement stream only** — the auth stream is never tracked, so it needs no tracking domain.

1. SES → **Configuration → Configuration sets** → on `cohwall-marketing` (Step 6a), open **Tracking options → Use a custom redirect domain**.
2. Enter `click.news.cohwall.com`; SES gives a **CNAME target** (region-specific). Add that CNAME (DNS only) in the Cloudflare `cohwall.com` zone.
3. HTTPS: provide an ACM cert for the subdomain when prompted to serve `https://` tracking links; plain HTTP works without but prefer HTTPS.

**Verify:** the tracking domain shows **Verified/Active** on `cohwall-marketing`.

## Step 6 — Configuration sets (the marketing/transactional split)  ☐
**Goal:** two sets so marketing is tracked and transactional is not.

Config sets aren't hard-bound to an identity — the mailer picks the set **per
message** (already wired in Phase 1). The mapping:

| Stream | Mailer / From | Config set |
|---|---|---|
| Transactional (`SessionMailer`) | `noreply@mail.cohwall.com` | `cohwall-transactional` |
| Marketing (`AnnouncementMailer`) | `news@news.cohwall.com` | `cohwall-marketing` |

**6a. `cohwall-marketing`**
1. Create configuration set `cohwall-marketing`.
2. **Tracking options** → custom redirect domain `click.news.cohwall.com` (Step 5).
3. **Event destination** → publish to **SNS** (topic from Step 7). Subscribe to:
   **Send, Delivery, Bounce, Complaint, Open, Click, Reject, Rendering Failure**.

**6b. `cohwall-transactional`**
1. Create configuration set `cohwall-transactional`.
2. **No** custom redirect domain.
3. **Event destination** → SNS. Subscribe to **Delivery, Bounce, Complaint,
   Reject, Rendering Failure** — **omit Open and Click**. Because the destination
   doesn't publish open/click, SES **won't inject the pixel or rewrite links** on
   magic-link mail (confirmed behavior). Bounces/complaints still protect us.

**Verify:** both sets exist; marketing lists Open+Click, transactional does not.

## Step 7 — SNS topic + HTTPS subscription  ☐
**Goal:** SES events reach `POST /webhooks/ses`.

1. SNS → **Create topic** (Standard) `cohwall-ses-events`. Both config sets in
   Step 6 publish here (one topic is fine; the payload carries the config-set name).
2. **Create subscription** → protocol **HTTPS** → endpoint `https://cohwall.com/webhooks/ses`.
3. The endpoint is **already deployed**, so the handshake confirms immediately:
   `Webhooks::SesController` auto-fetches the `SubscribeURL` on the first
   `SubscriptionConfirmation` hit. (If it's still `PendingConfirmation`, paste the
   `SubscribeURL` from the SNS console into a browser once.)

**Verify:** subscription state is **Confirmed**.

## Step 8 — Account-level suppression (the net)  ☐
**Goal:** SES auto-suppresses hard bounces/complaints so we never re-send, even if
an app-side write is missed. This is Cohwall's **primary** suppression today (no
`Subscriber` model yet), not just redundancy.

1. SES → **Configuration → Suppression list** → enable account-level suppression
   for **Bounces and Complaints**.

**Verify:** suppression reasons show Bounce + Complaint enabled.

## Step 9 — Request production access (sandbox exit)  ☐  ⏳ long-lead
**Goal:** leave the sandbox (sandbox = 200/day + only verified recipients).

1. SES → **Account dashboard → Request production access**.
2. In the request describe: transactional magic-links + event announcements to
   **registered attendees** (not cold marketing); bounce/complaint handling via
   SNS (Steps 6–8) and account-level suppression. This detail gets faster approval.
3. File this **as early as Steps 2–8 allow** — approval is typically ~24h and
   **gates the whole cutover**.

**Verify:** account shows **Production access: Enabled**; sending quota raised.

---

## Phase 0 done when…
- [ ] **Both** identities (`mail.` + `news.`) **Verified**, DKIM **Successful** (Step 2)
- [ ] MAIL FROM **Verified** on both (Step 3), DMARC published (Step 4)
- [ ] Tracking domain active on `cohwall-marketing` (Step 5)
- [ ] Both configuration sets present with the right event sets (Step 6)
- [ ] SNS topic created; subscription **Confirmed** (Step 7)
- [ ] Account suppression on (Step 8)
- [ ] **Production access enabled** (Step 9)
- [ ] `ses:` credentials added + deployed (see top)

## Go-live check (Phase 3)
While still in the sandbox, verify a recipient address in SES and send yourself a
magic-link + a test announcement; confirm DKIM `d=` is `mail.` vs `news.`
respectively (Gmail "Show original"), and that events land in the logs
(`kamal logs | grep SES`). Then flip once production access is green; watch SES
guardrails (<5% bounce, <0.1% complaint).

## Links
Decision: [[0008-email-relay-amazon-ses]] · Consent trail: [[0011-subscribers-and-consent-log]] (Inkwell — no Cohwall equivalent yet; the app-side marketing ingest waits on this)
