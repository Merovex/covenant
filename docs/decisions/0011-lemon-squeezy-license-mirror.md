---
type: decision
title: Lemon Squeezy mirror — licenses and orders, poll + webhook
status: accepted
tags: [rails, licenses, lemon-squeezy, integration, support, record-recordable]
created: 2026-08-23
updated: 2026-08-23
sources: [0009-support-desk-customers-licenses-tickets.md, 0007-versioned-recordables.md]
---

# 0011. Lemon Squeezy mirror — licenses and orders, poll + webhook

## Context
Verkilo sells through Lemon Squeezy (store 277638), which mints the license
keys customers activate the desktop app with. The support desk
([[0009-support-desk-customers-licenses-tickets]]) already has `License` and
`Customer`, but only hand-entered rows. Support needs every sold key — who
holds it, its status, how many machines it's on — in the desk, without
retyping it and without drifting from LS over time.

LS exposes the keys two ways: a REST API (`GET /v1/license-keys`, Bearer API
key, JSON:API, paginated, filter by store) and HMAC-signed webhooks
(`license_key_created` / `license_key_updated`). Both deliver the same
license-key resource. The key carries only `product_id`, so product names come
from `GET /v1/products`.

## Decision
**Mirror LS keys into `License` through one upsert, fed two ways.**

- `License::LemonSqueezy` (module, `app/models/license/lemon_squeezy.rb`) —
  thin `Net::HTTP` client (the `DownloadStat::Worker` pattern) + translation +
  `upsert(resource)`. A new key **originates** a `License` (creator
  `User.system`); a changed key **revises** it with a new `"synced"` event
  (added to `Recordable::EVENTS`); an unchanged key is a no-op; a key whose
  mirror staff have **trashed** is skipped, never re-originated. The buyer is
  matched to a `Customer` by normalised email (`find_or_create_by!`; an
  existing customer keeps their name).
- **Pull:** `SyncLemonSqueezyLicensesJob`, daily (5am) in `config/recurring.yml`
  (+ a "Sync from Lemon Squeezy" button on `/licenses`, `POST /licenses/sync`).
  The backstop that catches anything the webhook missed and the one-shot
  backfill.
- **Push:** `POST /webhooks/lemon_squeezy` (`Webhooks::LemonSqueezyController <
  ActionController::API`, no session/CSRF). Verifies `X-Signature` =
  HMAC-SHA256-hex(raw body, signing secret) with `secure_compare`; 404 when no
  secret is configured, 401 on a bad one; license-key events → the same
  upsert; other events are 200'd and ignored.
- **Schema:** `licenses` gains `external_id` (the LS key id — the idempotency
  handle, unique among *current* versions by validation, same trap as
  `license_key`), `external_order_id`, `activation_limit` (nil = unlimited),
  `instances_count`.
- **Mapping:** LS `inactive`/`active` → `active` (inactive only means
  not-yet-activated), `expired` → `expired`, `disabled` (or `disabled: true`)
  → `revoked`; `seats` ← `activation_limit || 1`; `issued_at` ← `created_at`.
- **Staff UI:** mirrored licenses show "Mirrored from Lemon Squeezy", the
  `XXXX-` short key, activations `used / limit`, LS key/order ids, and a
  lazy-loaded **"Activated machines"** panel (`GET /licenses/:id/activations`
  → `GET /v1/license-key-instances?filter[license_key_id]=`) listing each
  machine's name, instance id and activation time live from LS. Mirrored
  licenses can't be edited locally (edit/update redirect with an alert) — the
  next sync would overwrite the edit; edit in LS.
- **Secrets:** `lemon_squeezy_api_key`, `lemon_squeezy_webhook_secret`
  (optional `lemon_squeezy_store_id`) in Rails credentials; ENV
  (`LEMON_SQUEEZY_*`) overrides. No new Kamal secret — `RAILS_MASTER_KEY`
  already ships.

### Addendum (2026-08-23, same day) — orders
The key carries only an `order_id`; support also needs *what was paid, was it
refunded, where's the receipt*. So the same mirror now covers orders:

- **`Order`** — a **plain** table (not a recordable): LS owns the order and its
  one status flip (paid → refunded) is carried by `refunded`/`refunded_at`, so
  no version history is warranted. `external_id` has a real unique index (no
  versions to repeat it). Columns: `order_number`, `identifier`, `status`
  (pending/failed/paid/refunded), `refunded`, `refunded_at`, money as integer
  cents in `currency` (`subtotal`, `discount_total`, `tax`, `total`,
  `refunded_amount`) + `total_formatted`, `product_name`/`variant_name` (from
  `first_order_item`), `test_mode`, `ordered_at`. `belongs_to :customer`
  (matched by email like licenses); `Customer has_many :orders`
  (`restrict_with_error`).
- **Not stored: the receipt URL.** LS signs it with a short expiry (and re-signs
  on every fetch, which made the sync non-idempotent). `GET /orders/:id/receipt`
  asks LS for a fresh one and redirects.
- **Feeds:** `sync!` now walks `GET /v1/orders` before keys (tally becomes
  `{ orders: {…}, licenses: {…} }`); the webhook handles `order_created` and
  `order_refunded` through `upsert_order`. Register those two events in LS.
- **Links:** `License#order` / `Order#licenses` join on the LS order id both
  sides carry — no FK between them (a key can arrive before its order).
- **UI:** `/orders` (newest first, refunded filter) and `/orders/:id` (money
  breakdown, refund, LS ids, licenses from the order, receipt link); the
  license page's "Order" row; an "Orders" section on the customer page; a
  **Revenue** row on the dashboard (`Order.revenue(range)` — paid orders,
  refunds netted, test mode excluded, grouped by currency). App menu gains
  "Orders" (new `lucide/receipt.svg`). Status pills: paid → success,
  refunded/failed → danger, plus a neutral "Test" pill.
- `ApplicationHelper#money(cents, currency)` — "$28.00" for USD, "28.00 EUR"
  otherwise.

## Consequences
- Every LS change is a version on the spine — renewals, disables, new
  activations — so the license page's history is the audit trail, free.
- `instances_count` changes on each activation, so activation churn writes
  versions; accepted (that *is* support-relevant history).
- The LS API key is full-scope (LS has no read-only keys): treat it like the
  master key. It only lives in credentials.
- Orders are read-only in the desk — no form, no edit; refunds happen in LS
  and arrive by webhook/sync.
- Trashing a mirrored license in the desk is a deliberate opt-out of syncing
  that key; restoring it resumes.
- Minitest 6 dropped `minitest/mock`; `test_helper.rb` gained a small
  `stubbing(receiver, method, stand_in)` helper so tests never call LS.

## Alternatives considered
- **Webhook only** — real-time but no backfill of the already-issued key and
  no recovery from a missed delivery; kept as the fast path, not the source of
  truth.
- **Poll only** — simplest, but up to a day stale when a customer writes in
  minutes after buying; kept as the backstop.
- **Query LS live on every page** — no local rows, no history, and the desk's
  customer/ticket joins would have nothing to hang on. The activations panel
  is the one place we do go live, and lazily.
- **A separate `lemon_squeezy_licenses` table** — duplicates `License` and
  loses the spine's versioning/trash/notes for mirrored keys.

## Links
Related: [[0009-support-desk-customers-licenses-tickets]] ·
[[0007-versioned-recordables]] · [[support-desk-plan]]
Supersedes: — · Superseded by: —
