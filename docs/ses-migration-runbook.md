---
type: concept
title: SES/SNS migration runbook — Phase 0 (AWS + DNS)
status: active
tags: [rails, email, ses, sns, aws, dns, runbook, migration]
created: 2026-07-10
updated: 2026-07-10
sources: [decisions/0008-email-relay-amazon-ses.md]
---

# SES/SNS migration runbook — Phase 0 (AWS + DNS)

Operational checklist for the **prerequisite** AWS/DNS work behind
[[0008-email-relay-amazon-ses]]. Phase 0 is all console + DNS — **no app
code**. Work top to bottom; each step says how to verify it's green before the
next. Check boxes as you go; this is a living doc.

> **Why this order:** DNS propagation and the sandbox-exit approval (~24h) are
> the long-lead items — we file those early even though they're logically
> "later," to beat the next Mailgun invoice. One step (SNS subscription, 7) needs
> the Phase-2 webhook endpoint live to confirm; it's flagged where it bites.

## Variables

**Two sending identities** so transactional and marketing sign with different DKIM
`d=` domains — a spammy newsletter run can't drag magic-links toward spam. See
[[0008-email-relay-amazon-ses]] / the reputation-isolation rationale.

| Key | Value | Notes |
|-----|-------|-------|
| Root domain | `merovex.press` | org domain; DMARC published here covers all subdomains |
| AWS region | `us-east-1` | **confirm** — MAIL FROM MX + tracking CNAME targets are region-specific |
| **Transactional** identity | `auth.merovex.press` | magic-links; send `from: noreply@auth.merovex.press` |
| **Marketing** identity | `news.merovex.press` | newsletter; send `from: news@news.merovex.press` |
| Transactional MAIL FROM | `bounce.auth.merovex.press` | SPF alignment for the auth stream |
| Marketing MAIL FROM | `bounce.news.merovex.press` | SPF alignment for the news stream |
| Tracking (redirect) domain | `click.news.merovex.press` | branded open/click links — **marketing only** |
| Link host (email body URLs) | `merovex.press` | `default_url_options[:host]`; independent of the sending identity |
| SNS webhook URL | `https://merovex.press/webhooks/ses` | endpoint built in Phase 2 |
| DMARC report inbox | `dmarc@merovex.com` | cross-domain → needs the `_report._dmarc` authz record on merovex.com (Step 4) |

Where you edit DNS: **______** (registrar / Cloudflare / Route 53 — note it here).

> **Reputation split in one line:** transactional signs `d=auth.merovex.press`,
> marketing signs `d=news.merovex.press`; receivers score them separately, so the
> newsletter can never sink the login email. Config sets and suppression (below)
> keep the newsletter from souring the shared *account* reputation too.

---

## Step 1 — IAM sending identity  ☐
**Goal:** a least-privilege credential the app uses to call SES (nothing else).

1. IAM → **Users** → Create user `inkwell-ses` (no console access, programmatic only).
   The wizard's permissions step has **no inline-policy option** — pick **Attach
   policies directly**, select nothing, and finish.
2. Open the created user → **Permissions** tab → **Add permissions ▾ → Create
   inline policy → JSON** → paste, name it `inkwell-ses-send`, create:
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
   (We can tighten `Resource` to the verified-identity ARNs later, once they exist.)
   Alternatively: IAM → **Policies → Create policy** (same JSON) first, then attach
   it in the wizard — equivalent result.
3. On the user → **Security credentials → Create access key** → **Application
   running outside AWS** → save the **Access key ID** + **Secret**. This is the
   only time the secret is shown.

**Lands in Rails credentials (Phase 1):** `ses.access_key_id`, `ses.secret_access_key`, `ses.region`.
**Verify:** user exists with the inline policy; key pair saved somewhere safe (password manager, not the repo).

## Step 2 — Two domain identities + Easy DKIM  ☐
**Goal:** prove ownership and sign each stream with its **own** DKIM `d=` domain —
this is the reputation firewall between magic-links and the newsletter.

Do this **twice**, once per identity:

**2a. Transactional — `auth.merovex.press`**
1. SES → **Configuration → Identities → Create identity → Domain** → `auth.merovex.press`.
2. Enable **Easy DKIM**, key type **RSA 2048**.
3. Add the **3 CNAME** records SES shows (`<token>._domainkey.auth.merovex.press` → `<token>.dkim.amazonses.com`).

**2b. Marketing — `news.merovex.press`**
1. Same flow → `news.merovex.press`, Easy DKIM RSA 2048, add its **own 3 CNAMEs**.

(Only check "Publish DNS records to Route 53" if Route 53 hosts merovex.press; otherwise add records manually at your DNS host.)

**Verify:** **both** identities show **Verified** + DKIM **Successful** (minutes to a few hours). Don't request production access until both are green.

## Step 3 — Custom MAIL FROM subdomain per identity (SPF alignment)  ☐
**Goal:** SPF passes and *aligns* for DMARC on each stream (return-path lives under
the same brand, not `amazonses.com`).

Do this on **each** identity:

**3a. On `auth.merovex.press`** → MAIL FROM `bounce.auth.merovex.press`
   - **MX**: `bounce.auth.merovex.press` → `feedback-smtp.<region>.amazonses.com` (priority 10)
   - **TXT (SPF)**: `bounce.auth.merovex.press` → `"v=spf1 include:amazonses.com ~all"`

**3b. On `news.merovex.press`** → MAIL FROM `bounce.news.merovex.press`
   - **MX**: `bounce.news.merovex.press` → `feedback-smtp.<region>.amazonses.com` (priority 10)
   - **TXT (SPF)**: `bounce.news.merovex.press` → `"v=spf1 include:amazonses.com ~all"`

Leave the on-failure behaviour as **"Use amazonses.com as fallback"** until each verifies.

**Verify:** MAIL FROM shows **Verified** on both identities.

## Step 4 — DMARC  ☐
**Goal:** publish a DMARC policy (monitor first, tighten later).

Aggregate reports go to `dmarc@merovex.com` (a **different domain** than the
DMARC record), so `merovex.com` must authorize the cross-domain reporting — else
mailbox providers won't send the reports.

1. **DMARC record — on `merovex.press`** (org-level → covers `auth.` and `news.`).
   Cloudflare `merovex.press` zone → TXT, Name `_dmarc`:
   ```
   v=DMARC1; p=none; rua=mailto:dmarc@merovex.com; fo=1
   ```
2. **Cross-domain authorization — on `merovex.com`.** Cloudflare `merovex.com`
   zone → TXT, Name `merovex.press._report._dmarc`
   (→ `merovex.press._report._dmarc.merovex.com`):
   ```
   v=DMARC1;
   ```
   This is `merovex.com` saying "I accept DMARC reports for `merovex.press`."
   Without it the reports silently go nowhere.
3. **Mailbox:** ensure `dmarc@merovex.com` actually receives mail (real mailbox or
   catch-all with working MX on `merovex.com`), or the reports land nowhere.
4. Keep `p=none` through cutover; move to `quarantine`/`reject` only after a week+
   of clean aggregate reports.

**Verify** (Arch: `dig` needs `sudo pacman -S bind`; or use `drill`/`resolvectl`):
```
dig +short TXT _dmarc.merovex.press
dig +short TXT merovex.press._report._dmarc.merovex.com
```
Both should return their `v=DMARC1...` values.

## Step 5 — Custom open/click tracking domain (marketing only)  ☐
**Goal:** branded redirect links (`click.news.merovex.press`) instead of `*.awstrack.me` — better trust/deliverability. **Newsletter stream only** — the auth stream is never tracked, so it needs no tracking domain.

1. SES → **Configuration → Configuration sets** → on `inkwell-marketing` (Step 6a), open **Tracking options → Use a custom redirect domain**.
2. Enter `click.news.merovex.press`; SES gives a **CNAME target** (region-specific). Add that CNAME at your DNS host.
3. HTTPS: provide an ACM cert for the subdomain when prompted to serve `https://` tracking links; plain HTTP works without but prefer HTTPS.

**Verify:** the tracking domain shows **Verified/Active** on `inkwell-marketing`.

## Step 6 — Configuration sets (the marketing/transactional split)  ☐
**Goal:** two sets so marketing is tracked and transactional is not.

Config sets aren't hard-bound to an identity — the mailer picks the set **per
message** (Phase 1). The mapping we'll wire:

| Stream | Identity / From | Config set |
|---|---|---|
| Transactional (`SessionMailer`) | `noreply@auth.merovex.press` | `inkwell-transactional` |
| Marketing (`SubscriberMailer`, `PostBroadcastMailer`) | `news@news.merovex.press` | `inkwell-marketing` |

**6a. `inkwell-marketing`**
1. Create configuration set `inkwell-marketing`.
2. **Tracking options** → custom redirect domain `click.<YOURDOMAIN>` (Step 5).
3. **Event destination** → publish to **SNS** (topic from Step 7). Subscribe to:
   **Send, Delivery, Bounce, Complaint, Open, Click, Reject, Rendering Failure**.

**6b. `inkwell-transactional`**
1. Create configuration set `inkwell-transactional`.
2. **No** custom redirect domain.
3. **Event destination** → SNS. Subscribe to **Delivery, Bounce, Complaint,
   Reject, Rendering Failure** — **omit Open and Click**. Because the destination
   doesn't publish open/click, SES **won't inject the pixel or rewrite links** on
   magic-link mail (confirmed behaviour). Bounces/complaints still protect us.

**Verify:** both sets exist; marketing lists Open+Click, transactional does not.

## Step 7 — SNS topic + HTTPS subscription  ☐
**Goal:** SES events reach `POST /webhooks/ses`.

1. SNS → **Create topic** (Standard) e.g. `inkwell-ses-events`. Both config sets in
   Step 6 publish here (one topic is fine; the payload carries the config-set name).
2. **Create subscription** → protocol **HTTPS** → endpoint `https://merovex.press/webhooks/ses`.
3. ⚠️ **Ordering gotcha:** SNS immediately sends a `SubscriptionConfirmation` to
   that URL and stays **PendingConfirmation** until the endpoint confirms it.
   That endpoint is built in **Phase 2**. So either:
   - do Step 7 **after** Phase 2 deploys (cleanest), **or**
   - create it now and confirm later — the controller auto-confirms on first hit,
     or you can paste the `SubscribeURL` from the SNS console into a browser once.

**Verify:** subscription state is **Confirmed** (revisit after Phase 2 if needed).

## Step 8 — Account-level suppression (the net)  ☐
**Goal:** SES auto-suppresses hard bounces/complaints so we never re-send, even if
an app-side write is missed. App-side `Subscriber` stays source of truth (ADR 0011);
this is redundancy.

1. SES → **Configuration → Suppression list** → enable account-level suppression
   for **Bounces and Complaints**.

**Verify:** suppression reasons show Bounce + Complaint enabled.

## Step 9 — Request production access (sandbox exit)  ☐  ⏳ long-lead
**Goal:** leave the sandbox (sandbox = 200/day + only verified recipients).

1. SES → **Account dashboard → Request production access**.
2. In the request describe: transactional magic-links + opt-in double-confirmed
   newsletter; RFC 8058 one-click unsubscribe in every marketing email;
   bounce/complaint handling via SNS (Steps 6–8); consent log (ADR 0011). This
   detail gets faster approval.
3. File this **as early as Steps 2–8 allow** — approval is typically ~24h and
   **gates the whole cutover**.

**Verify:** account shows **Production access: Enabled**; sending quota raised.

---

## Phase 0 done when…
- [ ] **Both** identities (`auth.` + `news.`) **Verified**, DKIM **Successful** (Step 2)
- [ ] MAIL FROM **Verified** on both (Step 3), DMARC published (Step 4)
- [ ] Tracking domain active on `inkwell-marketing` (Step 5)
- [ ] Both configuration sets present with the right event sets (Step 6)
- [ ] SNS topic created; subscription **Confirmed** after Phase 2 (Step 7)
- [ ] Account suppression on (Step 8)
- [ ] **Production access enabled** (Step 9)

Then Phase 1 (sending) can flip. Gems for Phase 1 (reference): `aws-sdk-rails ~> 5`
+ `aws-actionmailer-ses ~> 1`; `delivery_method = :ses_v2`, `ses_v2_settings = { region: ... }`.

## Links
Decision: [[0008-email-relay-amazon-ses]] · Consent trail: [[0011-subscribers-and-consent-log]] (Inkwell — no Alcovo equivalent yet)
