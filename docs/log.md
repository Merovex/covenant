# Work Log

Append-only. Newest first. Format defined in [[CLAUDE]] (`CLAUDE.md`).

## [2026-07-22] refactor | Dropped the inbound autoresponder; press@ added as a second address
- **Removed the acknowledgement autoresponder.** `TicketsMailbox#open_ticket` no longer fires `TicketMailer.acknowledgement`; deleted the `acknowledgement` mailer action, both `ticket_mailer/acknowledgement.*` views, the mailer test, and the now-dead `ApplicationMailer.support_video_url` helper (+ its `:support/:video_url` credential). Rationale: a new ticket's opener is often spam/spoofed, and auto-replying to a forged From is backscatter that harms our *sending* reputation. Agents reply by hand.
- **Inbound addresses:** `support@verkilo.com` **and** `press@verkilo.com` are the two accepted localparts (no catch-all → SES drops the rest, killing scraped spam). Both open Tickets today via `ApplicationMailbox routing all: :tickets`; a dedicated `PressMailbox` is a later option if press needs different handling.
- **HEY-for-Domains considered and rejected** for the desk: it's a walled garden (no API/IMAP/webhook), so it can't feed the app's Ticket model — choosing it would mean shelving the built desk. Staying on SES inbound. (HEY/forward remains a fine choice for `press@` if app-tracking isn't wanted.)
- Mail tests green (5 runs). pages touched: [[ses-migration-runbook]], [[overview]], [[support-desk-plan]], [[log]]
- refs: `app/mailboxes/tickets_mailbox.rb`, `app/mailers/ticket_mailer.rb`, `app/mailers/application_mailer.rb`, `test/mailers/ticket_mailer_test.rb`

## [2026-07-22] build | SES wired for send+receive; runbook rewritten for verkilo.com
- **Reconciled the SES runbook against reality.** The old [[ses-migration-runbook]] was the Inkwell/`cohwall.com` doc dropped in verbatim: wrong app/domain, and it claimed the outbound send path + a `Webhooks::SesController` were "DONE on master" — neither existed here. Rewrote it for **Covenant / `verkilo.com`**, covering **both** send (ADR 0008) and inbound support mail (ADR 0010), and reflecting a **reused SES account** (IAM user, config sets, account suppression, production access = reuse+verify; identities/DNS + the whole inbound stack = new).
- **Layout:** transactional identity = `verkilo.com` apex (magic-links + `support@verkilo.com`, DKIM `d=verkilo.com`); marketing = `news.verkilo.com` (provisioned ahead, no `AnnouncementMailer` yet); inbound `support@verkilo.com` via S3 + receipt rule + apex MX + new `covenant-inbound` SNS topic → the `:ses` ingress.
- **Code wired (dormant until credentials exist):** added `aws-actionmailer-ses`; `production.rb` now sets `:ses_v2` delivery + `ses_v2_settings` (guarded by `credentials[:ses]`), the `:ses` Action Mailbox ingress + `subscribed_topics` (guarded by `credentials[:support][:sns_topic_arn]`), and `default_url_options` host `verkilo.com` (`APP_HOST` override). Booted prod config keyless → clean fallback (`delivery=smtp`, ingress nil). **Chose not to build** an outbound bounce/complaint webhook — account suppression is the net (no `Subscriber` model).
- **Erratum on [[0010-inbound-email-action-mailbox-ses]]:** it named the `:amazon` ingress (old `aws-sdk-rails`); the installed `aws-actionmailbox-ses` gem uses **`:ses`** (route `/rails/action_mailbox/ses/inbound_emails`). Added a dated note; ADR body left immutable.
- pages touched: [[ses-migration-runbook]] (rewrite), [[0010-inbound-email-action-mailbox-ses]] (erratum), [[index]], [[log]]
- refs: `Gemfile`, `config/environments/production.rb`

## [2026-07-22] note | Docs synced to the built support desk
- Rewrote [[overview]] (Alcovo → Covenant; single-tenant support desk; 2026-07-22 state: authed dashboard, ticket lifecycle, Pine, deferred SES). Marked [[support-desk-plan]] **BUILT** and rewrote its open items as resolved (final status set `open|pending|on_hold|resolved|closed`, system-user creator with required `Reply.creator`, partial-unique Message-ID index, inbound-domain config, autoresponder).
- New concept [[inactive-features]]: Posts/Forum/Chatroom (+ Categories, Comments) are hidden from nav but fully present in code — table of what's dormant, how it was hidden (menu/dashboard/root only), and how to bring one back. Chose to **document rather than relocate** (moving Rails code into a "nonactive" folder fights Zeitwerk for no gain).
- Also shipped small UI fixes: "My Profile" now links to the working name/avatar page (relabelled from "Settings"); breadcrumbs drop the leading house + slash (home lives in the header).
- pages touched: [[overview]], [[index]], [[support-desk-plan]], [[inactive-features]] (new), [[log]]

## [2026-07-22] build | App renamed Covenant; authed dashboard home; support-only nav
- Renamed the app **Alcovo → Covenant** across `app/`, `config/` (incl. `module Covenant`), the autosave localStorage prefix, and Kamal `deploy.yml` service/image/volume. `docs/` left as historical record (the plan already notes Alcovo ≡ Covenant). No `Alcovo::` constant was referenced anywhere, so the module rename was inert.
- **Whole site behind auth**: dropped `allow_unauthenticated_access` from the styleguide (`StaticController`); only session/setup/signup stay public. Root is now a real **dashboard** (`DashboardController#show`), not the styleguide.
- **Dashboard** = admin's support-desk home: top row of "new licenses" stat cards (Today / This week / This month / This year, counted off `Record.active.licenses.created_at`) + section tiles (Tickets/Customers/Licenses). Non-admins get nothing. Hid Posts/Forum/Chatroom (+ Categories, recents) from the app menu — this install is a support desk.
- **Dev sign-in**: `User#send_magic_link` now returns the `SignInCode`; `Authentication#expose_dev_sign_in_code` stashes its plaintext in the flash **only in development**, and the "check your email" page shows it with a one-click "Sign in now" link — no mailbox needed. Production never sees it.
- **Bootstrap fix**: the seeded system user was making `/setup` think the install already had users. Added `User.people` (non-system) and keyed `SetupsController#require_no_users` + `SessionsController#new` off it, so first-run setup still works.
- Tests: +dashboard integration + updated auth-flow (root now redirects unauthenticated); suite 200 green, RuboCop clean.
- pages touched: [[log]]
- refs: app/controllers/{dashboard,sessions,setups,static}_controller.rb, app/controllers/concerns/authentication.rb, app/models/{user,setup}.rb, app/views/dashboard/*, config/{application,routes,deploy}

## [2026-07-22] build | Support desk implemented (SES integration deferred)
- Built [[support-desk-plan]] end to end minus live SES. Schema: `customers` (plain), `licenses`/`tickets`/`replies` (recordables). Models include `Recordable` directly (immutable, `mutable? = false`); `Ticket`/`Reply` carry `has_rich_text :content` and copy the body forward in `build_successor` like `Comment`. `Record` gained the three types + scopes + `generates_token_for :ticket_reply`; `Ticket#replies` mirrors `Record#comments`.
- Resolved open items at execution: **ticket status** = open|pending|closed (no "resolved"); **inbound creator** = seeded system `User` (`role: :system`, `User.system`) stamped on inbound tickets/replies — the spine's `records.creator_id` is NOT NULL, so a truly nil creator can't reach it (the plan's "nullable creator" is a column-only affordance, `Reply.creator` stays required via `Recordable`); **license-key uniqueness** = validation among `License.current`; **Message-ID dedup** = *partial* unique index scoped to `event = 'created'` (successor versions repeat the id, so a bare unique index was wrong — the same trap as `license_key`).
- Inbound routing extracts the token straight from `In-Reply-To`/`References` Message-IDs (not plus-addressing — the outbound From stays clean `support@`), falls back to stored-Message-ID matching, then opens a new ticket. `TicketMailer#acknowledgement` is the autoresponder fired on inbound-opened tickets (Basecamp-style 24/5 copy, branded Covenant). Desk is admin-only (agents = `domain_admin`).
- Theme repointed to **Pine** (brand tokens' chroma dropped ~75%, light + both dark blocks). New CSS: `status-pill`, `ticket`, `.comment--outbound`. App menu gains a Tickets card + admin links. SES/AWS prod config left commented (gem: `aws-actionmailbox-ses`, ingress `:ses`).
- Tests: 4 model + mailbox + mailer + integration (26 new); full suite 196 green, RuboCop clean.
- pages touched: [[support-desk-plan]], [[log]]
- refs: db/migrate/2026072207000{1..4}, app/{models,mailers,mailboxes,controllers,policies}, app/assets/stylesheets/{01-tokens,status-pill,ticket,comment}.css

## [2026-07-22] decision | Inbound support email — Action Mailbox + Message-ID token routing (ADR 0010)
- Filed [[0010-inbound-email-action-mailbox-ses]] (accepted). Receive via Action Mailbox `:amazon` ingress (SES receipt rule → SNS → `/rails/action_mailbox/amazon/inbound_emails`). Route by a signed `generates_token_for(:ticket_reply)` token on the stable `Record`, carried in our outbound `Message-ID` (`<reply-<record_id>-<token>@domain>`) and echoed back by the client in `In-Reply-To`/`References` — the 37signals/Help Scout pattern (verified against a real Basecamp support .eml: clean `support@`, no Reply-To, token in the Message-ID), improved with a crypto token. Precedence: token → direct Message-ID match → new ticket. Sender email resolves the Customer only; dedup on Message-ID for idempotent ingest.
- Extends [[0008-email-relay-amazon-ses]] (send-only): adds an inbound SES receipt rule + MX + SNS topic — needs an inbound section in [[ses-migration-runbook]]. Plus-addressed Reply-To rejected as primary (uglier address); sender-email routing rejected (ambiguous with multiple tickets per customer).
- pages touched: [[0010-inbound-email-action-mailbox-ses]] (new), [[support-desk-plan]], [[index]]
- refs: ~/Downloads/2204298019 - Re_ Copy Link doesn't work in Android.eml (Help Scout specimen)

## [2026-07-22] decision | Support desk domain — Customers, Licenses, Tickets, Replies (ADR 0009)
- Filed [[0009-support-desk-customers-licenses-tickets]] (accepted) + [[support-desk-plan]] (self-contained build plan). Additive on the existing spine ([[0006-record-recordable-generic-spine]]/[[0007-versioned-recordables]]), single-tenant, SQLite. `Customer` = plain table (the collector, not a User). `License`/`Ticket`/`Reply` = recordables (not Publishable), immutable → free audit history. Ticket `has_rich_text` the customer's opening email; each later message is a `Reply` (inbound/outbound, nullable creator) threaded under the ticket's record via `parent_id`; `Ticket#replies` mirrors `Record#comments`. Accent theme → Pine (token repoint only); CSS stays CUBE/BEM per [[css-architecture]].
- Open items recorded in the plan: ticket status set, inbound-ticket creator (system user vs nullable), license-key uniqueness among `current`, attachments (phase 2), inbound domain.
- pages touched: [[0009-support-desk-customers-licenses-tickets]] (new), [[support-desk-plan]] (new), [[index]]
- refs: docs/support-desk-plan.md

## [2026-07-10] ingest | SES/SNS Phase-0 runbook ported from Inkwell
- Brought over Inkwell's `ses-migration-runbook.md` **verbatim** (per request): the operational Phase-0 AWS/DNS checklist (IAM, DKIM, MAIL FROM/SPF, DMARC, tracking domain, Configuration Sets, SNS webhook, account suppression, sandbox-exit). Inkwell naming left intact (`inkwell-ses`, `inkwell-marketing/-transactional`, `merovex.press`) — rename at execution. Only the ADR cross-links were repointed: `[[0015-…]]` → Alcovo's [[0008-email-relay-amazon-ses]]. The consent-log link `[[0011-subscribers-and-consent-log]]` is an Inkwell reference with no Alcovo equivalent and dangles by design (flagged inline).
- Caveat recorded: the runbook's marketing/newsletter half (marketing identity, tracking domain, `SubscriberMailer`/`PostBroadcastMailer`, consent log) describes features Alcovo does not have — provisioning-ahead, not current scope.
- pages touched: [[ses-migration-runbook]] (new), [[0008-email-relay-amazon-ses]], [[index]]
- refs: ../docs/ses-migration-runbook.md

## [2026-07-10] decision | Email relay — adopt Amazon SES/SNS (ADR 0008)
- Filed [[0008-email-relay-amazon-ses]] (accepted). Alcovo sends only transactional magic-links today and prod mail is unconfigured (`letter_opener` in dev), so this is a **greenfield SES adoption**, not a Mailgun migration — the ADR reframes Inkwell's 0015 accordingly. Decision: Action Mailer `:ses_v2` via `aws-sdk-rails`, SNS→HTTPS webhook ingest, two sending identities (transactional now, marketing provisioned-ahead), SES account suppression. Anchors the Phase-0 runbook.
- Open dependency noted: no Alcovo subscribers/consent ADR (Inkwell's 0011) — the marketing stream stays aspirational until one exists.
- pages touched: [[0008-email-relay-amazon-ses]] (new), [[index]]
- refs: ../config/environments/production.rb:63, ../app/mailers/session_mailer.rb

## [2026-07-10] build | App menu (jump-to sheet) ported from Inkwell
- Brought over Inkwell's Basecamp-style global nav and trimmed it to Alcovo's routes. Header's plain "Alcovo" brand link became a house home-icon (→ root) + an "Alcovo ⌄" popover trigger that opens `layouts/_app_menu` — a native-Popover command sheet with a card grid (Posts/Forum/Chatroom), a type-to-filter search, a "Go to" list, and Recent records. `AppMenuHelper` + `app-menu` Stimulus controller (type-to-filter, ↑/↓/Enter) + `app-menu.css` copied in (CSS auto-bundles via `:app`; controller eager-loads). Added `Record.recently_active` scope for the recents list; recents limited to `Post`/`Message` (the recordables with a standalone page), linked by Record id.
- Removed as irrelevant to Alcovo: Books, Series, Authors, Subscribers, Broadcasts, Analytics, System settings. Categories gated to `domain_admin?` to match its controller `authorize!` (open call noted in the concept page). Downloaded real Lucide `file-text`/`messages-square`/`message-circle` SVGs from source (never hand-drawn). Verified by rendering both partials via `ApplicationController.render` (no server run).
- pages touched: [[app-menu]] (new), [[index]]
- refs: ../app/views/layouts/{_header,_app_menu}.html.erb, ../app/helpers/app_menu_helper.rb, ../app/javascript/controllers/app_menu_controller.js, ../app/assets/stylesheets/app-menu.css, ../app/models/record.rb:28

## [2026-07-04] note | CSS architecture page — the CUBE/BEM hybrid, written down
- New concept page describing the styling methodology: CUBE decides the rule's kind and cascade home (compositions + utilities in `u-*` files, standard BEM blocks one-per-file, exceptions as modifiers/data-attributes), BEM names the block internals. Covers the Propshaft one-link-per-file + `@layer base, components, utilities` delivery, the two token sources (Open Props for non-color, our OKLCH semantic colors), the "standard components, never bespoke" rule, and a decision ladder for adding styles.
- pages touched: [[css-architecture]] (new), index.md
- refs: ../app/assets/stylesheets/application.css, ../app/assets/stylesheets/00-layers.css

## [2026-07-04] note | Playbook now carries the actual color settings
- Added the shipped OKLCH values and the derivation rule to the theme playbook: tints are Tailwind v4 `-200` shades desaturated by 15% (keep L/H, chroma ×0.85), and the teal brand ramp follows the same −15% chroma rule (teal-950/-800/-700/-500/-100 by role). The add-a-tint procedure now shows the recipe applied (slate-200 → `oklch(92.9% 0.011 255.508)`).
- pages touched: [[theme-model-playbook]]
- refs: ../app/assets/stylesheets/01-tokens.css:74, [[theme-background-colors]]

## [2026-07-04] note | Theme model playbook — mode / tint / accent axes + how-to
- Interrogated the runtime appearance system and wrote a task-oriented playbook: three orthogonal axes (mode `data-theme` light/dark/auto, rotating `data-tint` background, fixed teal accent/brand), all resolved in 01-tokens.css and steered by two `<html>` attributes rendered from sanitized cookies. Documents the cookie→helper→attribute→token→component flow and step-by-step procedures (add/remove/reorder tints, change defaults, change accent, add tokens, wire toggles) plus gotchas (accent doesn't rotate; duplicated dark blocks; cascade order; doc-only `--accent-pale`).
- pages touched: [[theme-model-playbook]] (new), index.md
- refs: ../app/assets/stylesheets/01-tokens.css, ../app/javascript/controllers/{theme,tint}_controller.js, ../app/controllers/application_controller.rb:29, ../app/views/layouts/_header.html.erb

## [2026-07-03] tweak | Context menu flush to the canvas corner; X mirrors the trigger
- `.menu--context` now compensates on both axes (negative end margin + negative quarter-pad top margin) so the panel hugs the canvas's top-right corner exactly, and its top-end radius matches the canvas corner. The X close is inset quarter-pad down / half-pad in — the exact spot the ⋯ trigger occupies on the page, so opening the menu reads as the trigger flipping to an X.
- refs: menu.css

## [2026-07-03] tweak | ⋯ and X triggers sized to match head buttons
- The ⋯ trigger and the menu's X close are now 32px squares matching the other head buttons. The trigger sits half a pad in from the canvas edge (`.canvas__head-actions` end padding); the anchored popover compensates with a negative end margin on `.menu--context` so the panel itself stays flush to the canvas's right, as before.
- refs: canvas.css, menu.css

## [2026-07-03] tweak | Head-action buttons taller
- Canvas-head buttons (Update / Never mind / Edit / Save draft / Publish …) grew from 24px to 32px (`block-size: 2 * --u-pad`) — halving the air above/below to about a quarter-pad each side. The strip's 40px min-height is unchanged.
- refs: canvas.css

## [2026-07-03] fix | Context menu close (X) restored
- The ⋯ popover's internal close button (menu__close, top-right — the space `.menu--context`'s padding-block-start reserves) had been lost in the canvas_head rework. Restored: ghost icon X with `popovertargetaction="hide"`, no JS.
- refs: shared/_canvas_head.html.erb

## [2026-07-03] tweak | List views lose the context menu; house breadcrumb
- Context menus are for individual records only: the posts index and Post Drafts heads are now breadcrumb-only. Gotcha: `block_given?` isn't reliable in partials (the renderer supplies a block context), so an empty ⋯ shell still rendered — the partial now `capture`s the block and branches on `actions.present?`. Test pins the no-menu index. Post Drafts gained the same "New post" perma-header button as the index to replace its menu items.
- The breadcrumb's leading "Alcovo" is now a house icon (lucide house.svg, vendored), auto-prepended by the partial as the home link — all callers dropped their `["Alcovo", root_path]` crumb; separators now precede every listed crumb.
- refs: shared/_canvas_head.html.erb, breadcrumb.css, posts/index+drafts views, all crumb callers

## [2026-07-03] tweak | Pinned flag in the published list
- Pinned posts show a "📌 Pinned" pill in the index rows — the `.scheduled-badge` generalized into `.list__flag` (moved scheduler.css → list.css; both the drafts clock flag and the new pin flag use it; solid primary pill, same metrics). `_list_item` gained `pinned:` alongside `scheduled_at:`. Ordering was already right (`feed_ordered` sorts `pinned_at DESC NULLS LAST` first) — now it's visible; test pins a post older than a fresh one and asserts it tops the list with the flag. Lucide pin.svg vendored. Also `Record.originate` sets the record's creator from the first version explicitly (was leaning on `Current.user`, nil outside requests).
- refs: list.css, scheduler.css, shared/_list_item.html.erb, posts/index.html.erb, record.rb, posts_controller_test.rb, posts_drafts_test.rb

## [2026-07-03] tweak | Edit out of the context menu; menu reordered
- Basecamp-style: Edit is the most common action, so it's now a standalone link beside the ⋯ trigger — `shared/_canvas_head` gained an `edit_href:` local (short ghost button, same head-action sizing as the menu:false clusters). The show-page menu is now: Pin/Unpin · Revert to draft (or Publish for drafts) · — · **View History** (renamed from Change Log in the menu; the page keeps its title) · — · Move to trash. Separators above View History and Move to trash.
- Follow-up: the head is `justify-content: space-between`, so Edit + trigger (+ popover) now share one flex child — new `.canvas__head-actions` wrapper (quarter-pad gap, no end padding so the ⋯ stays flush right) instead of three spread-out children.
- refs: shared/_canvas_head.html.erb, posts/show.html.erb, canvas.css

## [2026-07-03] refactor | DHH-review remedies (Post implementation)
- **Transition ladder into the model**: `Record#save_edit` now takes intent kwargs (`publish:`, `schedule_at:`, `unschedule:`) — a requested transition wins and folds the edit into the transition version; otherwise the regime rule. `Post#publish/schedule/unschedule` accept `**changes` + `creator:`. `PostsController#update` gutted to one call + one branch (was four jobs on param sniffing).
- **`Record.originate(version)`**: the record-birth dance (row → first version → cursor, one transaction) moved from the controller to the spine.
- **Past-schedule guard is a model validation** (`appointment_in_future`, on new scheduled versions only — an existing appointment naturally becomes past) — the predicate-that-writes controller helper is gone; create keeps a one-line pre-flight (no record exists yet to revise).
- Nits: `amend` de-golfed (and its local no longer shadows `#content`); `Record.posts` scope replaces the thrice-repeated `where(recordable_type: "Post")`; `Posts::DraftsController` includes `PostScoped`; `scheduled_at` memoized; `PublishLaterJob` de-defended (expanded guards, no `&.`); helper's updated-branch boiled to two arms; index counts via one `group(:status).count`.
- Behavior unchanged: all 77 tests green without modification. ADR 0007 consequences updated (originate + ladder).
- refs: record.rb, post.rb, posts_controller.rb, concerns/post_scoped.rb, posts/drafts_controller.rb, jobs/post/publish_later_job.rb, posts_helper.rb

## [2026-07-03] fix | Trashcan no longer covered by the row link
- The stretched row link (`.list__body::after`, inset 0) was capturing the trashcan's clicks despite the action's z-index. Fixed structurally: on rows with a `.list__action`, the overlay stops 3.5rem short of the inline end (`:has()` — the app already requires modern browsers), so the trash zone is simply outside the link. z-index lift kept as belt-and-suspenders.
- refs: list.css

## [2026-07-03] build | Trash retention clocks + drafts trashcan
- **Retention policy as data**: `records.purge_after` (indexed) set at trash time from `Recordable#retention_period` — 30 days default; `Post` overrides to **2 years when `ever_published?`** (any version with status published; scheduled-never-published doesn't count) — legal hold: exposure outlives the unpublish button. `restore` clears it. `Record.purgeable` scope + `Record::PurgeTrashJob` wired into config/recurring.yml (4am daily, production).
- **Post Drafts trashcan** (far right, above the stretched row link via `.list__action`): never-published drafts are destroyed **outright** (per user: "toss immediately" — no trash ceremony; `turbo_confirm` warns no-undo; `PublishLaterJob` gains `discard_on DeserializationError` for tossed scheduled posts). A *reverted once-published* draft can't be shredded: the same button routes it to the trash on the two-year clock, with matching confirm copy. Currently-published posts rejected outright. Lucide trash-2.svg vendored.
- refs: db/migrate/20260703300001, record.rb, concerns/recordable.rb, post.rb, jobs/record/purge_trash_job.rb, jobs/post/publish_later_job.rb, posts/drafts_controller.rb, shared/_list_item.html.erb, posts/drafts/index.html.erb, list.css, config/recurring.yml, routes.rb, posts_drafts_test.rb

## [2026-07-03] tweak | Scheduled badge → solid primary pill
- `.scheduled-badge` is now a solid pill: `--brand-strong` (teal-800) + white — the same AAA pair as the primary button, both modes — with `.badge` metrics (radius-round, same padding). Was quiet teal text; user wanted it to stand out. Follow-up: `align-self: start` so it shrink-wraps inside `.list__body`'s column flex instead of stretching full width.
- refs: scheduler.css

## [2026-07-03] tweak | "Posts on <time>" badge for scheduled rows in Post Drafts
- Scheduled rows in Post Drafts show a clock badge — "Posts on Jul 4 at 11:00" — localized to the browser zone/locale. `shared/_list_item` gained an optional `scheduled_at:` local (renders the badge under the meta line); `local-time` controller upgraded to locale-aware time (12h/24h follows the browser, replacing HEY's dual-format trick) with an optional weekday value (composer head keeps "Fri, Jul 3…"). Byline label simplified to "Scheduled" — the badge carries the specifics. `.scheduled-badge` styled in brand-text teal, tokens only.
- refs: shared/_list_item.html.erb, posts/drafts/index.html.erb, local_time_controller.js, posts/_composer_actions.html.erb, scheduler.css, posts_drafts_test.rb

## [2026-07-03] build | Reschedule composer for scheduled posts
- Editing a scheduled post gets its own head: reschedule clock + "Post on <time>" (localized to the browser zone by a new `local-time` controller) + Never mind + **Save** (plain save keeps the appointment — panel fields stay disabled while closed). The scheduler panel gains an editing mode: appointment preselected (server renders app-zone fallback; `schedule-defaults` controller corrects to browser zone), **Save** (reschedules — a fresh `scheduled` event + job; stale jobs no-op), **Post now instead** (flips the flag false + publish → published stamped now), and an inline **unschedule and save** footnote submit. New `unscheduled` event + `Post#unschedule` (→ drafted, `published_at` cleared — it was a booking, not a publish date). Controller: `unscheduling?` branch (flag=false, not publishing, currently scheduled) so the show-page rename PATCH stays unaffected.
- refs: shared/_scheduler.html.erb, posts/_composer_actions.html.erb, posts_controller.rb, post.rb, concerns/recordable.rb, schedule_defaults_controller.js, local_time_controller.js, scheduler.css, posts_helper.rb, posts_scheduling_test.rb

## [2026-07-03] fix | Scheduling respects the browser's time zone
- Scheduled times were parsed in the app zone (UTC), so "11:00" picked at 10:35 EDT was 7:00 AM local — already past — and `Post::PublishLaterJob`'s `wait_until` fired immediately, insta-publishing the "scheduled" post (and making subsequent edits version-track, since the post was now genuinely published). Scheduler panel now carries a hidden `scheduled_posting_at_zone` filled by a tiny `timezone` Stimulus controller (`Intl.DateTimeFormat().resolvedOptions().timeZone`); the server parses the appointment via `Time.find_zone(zone).local(...)` (app-zone fallback). Plus a guard: scheduling a time that already passed 422s with "That scheduled time has already passed" instead of silently publishing — on both create and update, before anything saves.
- refs: timezone_controller.js, shared/_scheduler.html.erb, posts_controller.rb, posts_scheduling_test.rb

## [2026-07-03] fix | Scheduler polish (icon, order, popover placement) + drafts naming
- Clock icon was crushed to ~2px: the head-cluster button rule's padding-inline + `aspect-ratio: 1` left a sliver of content box and the SVG flex-shrank — icon buttons in the cluster now get `padding-inline: 0`. Clock moved BEFORE Save draft. Scheduler popover pinned to the screen's left edge: bare `.menu` popovers rely on the UA `[popover] inset: 0`, and in the over-constrained fixed box `left: 0` beats the controller's `inset-inline-end` — `anchored-popover#reposition` now also sets `inset-inline-start/inset-block-end: auto` (fixes every bare-menu dropdown, e.g. list-view sort menus), plus a no-JS fallback inset on `.scheduler`. "Edit your…" link moved ABOVE the published list. Drafts page renamed **Post Drafts** (heading, crumb, title).
- refs: canvas.css, scheduler.css, anchored_popover_controller.js, posts/_composer_actions.html.erb, posts/index.html.erb, posts/drafts/index.html.erb

## [2026-07-03] build | Published-only index + counted drafts link
- `/posts` now lists only published posts (`Post.current.published`, via a new `Post.current` scope = current versions of untrashed records — also refactored into the index). Below the list, a counted link to `/posts/drafts` worded by what exists: "Edit your N drafts…" / "Edit your N scheduled posts" / "Edit your N scheduled posts and M drafts…" (posts, not "messages"; hidden when everything's published). `Posts::DraftsController#index` lists drafts + scheduled (most recently touched first), rows linking straight into the composer, with Scheduled/Draft labels.
- refs: posts_controller.rb, posts/drafts_controller.rb, posts/drafts/index.html.erb, posts/index.html.erb, posts_helper.rb, post.rb, routes.rb, posts_drafts_test.rb

## [2026-07-03] build | Post scheduling ("When would you like to post this?")
- Third publication path: **scheduled** — a new `status` value + `scheduled` event. Scheduling is a transition version (`event: scheduled`, `published_at` = the appointment); the post then stays **mutable** (`mutable? = drafted? || scheduled?`) — edits amend silently until `Post::PublishLaterJob` (Active Job, `wait_until:` the appointment) publishes it, stamped with the scheduled time. Job guards no-op on trash/early-publish/reschedule (each reschedule enqueues its own job; stale ones fail the `published_at.future?` check). Publishing early discards the future date and stamps now (`publish` keeps `published_at` only when already past).
- UI per spec, adapted to house components + **native popover protocol** (not `<dialog>`): clock trigger (`popovertarget`) + `.scheduler` panel riding the `.menu` popover shell with `anchored-popover` placement below; date select (Today/Tomorrow/+28, ISO values, default Tomorrow), hour select (0–23, default 9), "Schedule and save" submits the composer form; hidden `scheduled_posting` flag flipped to "true" by a new `set-input` Stimulus controller; all panel controls start `disabled` and a `controls-disabler` controller syncs them to the popover's native `toggle` event, so ordinary saves never carry scheduler fields. Composer head actions extracted to `posts/_composer_actions` (state-aware: published → Update/Never mind; draft/scheduled → Save draft/clock/Publish); scheduler itself is `shared/_scheduler` (form id parameterized) for reuse. Lucide clock.svg vendored from source. Index shows "Scheduled <date>", show page a "Scheduled · <time>" badge, change log narrates "scheduled this post to publish <time>".
- refs: post.rb, concerns/recordable.rb, jobs/post/publish_later_job.rb, posts_controller.rb, shared/_scheduler.html.erb, posts/_composer_actions.html.erb, posts/new+edit+show+index views, set_input_controller.js, controls_disabler_controller.js, scheduler.css, lucide/clock.svg, posts_helper.rb, posts_scheduling_test.rb

## [2026-07-03] tweak | "Change Log" naming + published-edit buttons
- History view renamed **Change Log** everywhere (page heading, crumbs, page titles, the ⋯ menu item, and the back-links from change/version pages). Editing a *published* post now offers **Update** (primary) + **Never mind** (link back to the post) instead of Save draft/Publish; drafts keep Save draft + Publish.
- refs: posts/events/index.html.erb, posts/changes/show.html.erb, posts/versions/show.html.erb, posts/show.html.erb, posts/edit.html.erb, posts_controller_test.rb

## [2026-07-03] fix | Changes page = past version vs CURRENT (Basecamp URL shape)
- Per user correction (replacing the short-lived inline `<details>` compare): each past stop that differs from the current version gets a **"See the changes"** link → `/posts/:record_id/changes/:old_version_id`, and that page diffs the OLD version (deletions) against the CURRENT version (insertions) — not against its neighbor. Title renders as del/ins in the header; byline reads "Changes since the version from … by …". Link presence decided by column compare (body_id/title), so the events feed stays free of rich-text loads. Test proves non-adjacency: a v1 change page shows edits introduced two versions later.
- refs: posts/changes_controller.rb, posts/changes/show.html.erb, posts/events/index.html.erb, posts/events_controller.rb, posts_helper.rb, history.css, posts_history_test.rb

## [2026-07-03] tweak | Events feed as a vertical subway line
- The change-history feed renders as a subway line: a continuous 3px rail in `--accent` teal with a canvas-filled, teal-ringed stop at each event; rail spans entries + gaps and trims to the terminal stops (first/last-child; hidden for a single entry). List is half the canvas width, centered (full width under 48rem). All sizes tunable via `--history-*` custom properties; colors token-only, mode-aware.
- refs: history.css

## [2026-07-03] build | Versioned recordables + change history (ADR 0007)
- Recordables are now immutable event-tagged versions. `posts` gained `record_id` (back-pointer), `creator_id` (per-version actor), `event` (created/updated/published/unpublished/pinned/unpinned/trashed/restored — display tag, prefix-enumed; state queries stay on `status`), `body_id` → new `bodies` table (shareable rich-text owner: content edits mint a new Body via `Post#content=`; action-only versions share; "did the body change" = integer compare). Backfill migration moved existing rich text Post→Body. Records' cursor (`recordable_id`) made DB-nullable for the create transaction only.
- Spine API on Record: `versions`, `revise` (build successor via dup → insert → repoint cursor, transactional; invalid version leaves cursor alone), `save_edit` (regime rule: `mutable?`/drafted → amend in place, published → version per save; transitions always revise), `trash`/`restore` (event version + `trashed_at` cache — trash is tracked draft OR published). Record destroy cascades versions and garbage-collects orphaned bodies.
- **Identity re-keyed: `/posts/:id` is the Record id** (Basecamp-style; version ids are ephemeral). `PostScoped` controller concern resolves record + current version everywhere. Publish/pin as resources; composer Publish folds edits into the published version; inline rename of a live post = tracked title change.
- History UI: `/posts/:id/events` (feed lines derived from adjacent-version deltas — event tag, title from/to, body_id compare; zero rich-text loads), `/posts/:id/changes/:version_id` (word-level tracked-changes diff: `diff-lcs` gem + in-repo `HtmlDiff`, ins/del styled via success/danger tokens in history.css), `/posts/:id/versions/:version_id` (frozen render). Context menu: added **View changes**, removed Rename (title click covers it), Pin/Unpin for published posts.
- Tests: 53 runs green (regime branches, publish-date preservation across versions, body sharing vs minting, trash events, cascade destroy, the full six-line draft→publish→edit→revert→redraft→publish scenario, title from/to line, diff ins/del, frozen version). Rubocop clean.
- pages touched: [[0007-versioned-recordables]], [[overview]], [[index]]
- refs: db/migrate/20260703200001-3, record.rb, concerns/recordable.rb, post.rb, body.rb, html_diff.rb, posts_controller.rb, posts/{publishes,pins,events,changes,versions}_controller.rb, concerns/post_scoped.rb, posts_helper.rb, posts views, history.css, routes.rb, Gemfile (diff-lcs)

## [2026-07-03] tweak | Shorter head-action buttons, standard strip height
- Canvas-head action buttons (menu: false cluster) are now a short variant: fixed `block-size: 1.5 * --u-pad` (24px), zero block padding (inline-flex centers the label), small font — leaving ~half a pad of air above/below inside the strip. `.canvas__head` gains `min-block-size: 2.5 * --u-pad` (≈ the ⋯ icon-button height) so menu-less heads keep exactly the standard strip height instead of shrinking or growing. Cluster gets half-pad inline-end padding so buttons aren't flush against the rounded corner.
- refs: canvas.css

## [2026-07-03] fix | Composer pages use the standard canvas head
- New/edit now open with the standard breadcrumb head (Alcovo / Posts / …) like the item view — per user correction; the "New post"/"Edit post" perma-headers are gone (the composer title speaks for itself). The head's right side carries **Save draft** + **Publish** (primary) instead of the ⋯ menu: `shared/_canvas_head` gained a `menu:` local (default true = popover as before; false = block yields buttons in a `.u-cluster`). Buttons submit the composer form from outside it via the HTML `form="composer"` attribute; Publish sends `publish=1` and the controller publishes after save. The show-page rename form hits the same `update` with no publish param, so renames never touch status (covered by test). "Save draft" on an already-published post keeps it published for now — unpublish stays in the show page's ⋯ menu; flip later if draft-on-save is wanted.
- refs: shared/_canvas_head.html.erb, posts/new+edit.html.erb, posts/_form.html.erb, posts_controller.rb, posts_controller_test.rb

## [2026-07-03] build | Borderless composer for the post form
- New `composer.css`: bare H1-scale title input (no border/outline, placeholder, `--font-size-6`/weight-8 to match page titles) + frameless Lexxy (`border: none`, transparent bg, full-width toolbar with just its hairline; `--lexxy-editor-padding: var(--u-pad)` keeps text off the edges; toolbar padding-inline optically aligns first icon with title/body text). `_form` dropped `.field` wrappers and visible labels — accessible names via `aria-label`; body gets a "Write away…" placeholder for affordance (Lexxy renders placeholders natively). Error summary + submit row unchanged.
- refs: composer.css, posts/_form.html.erb

## [2026-07-03] build | Lexxy dark mode via token bridge
- Lexxy paints (editor + rendered `.lexxy-content`) entirely from `--lexxy-*` :root variables, shipped light-only — hence black body text on the dark canvas. Added `lexxy-theme.css` remapping them onto our semantic tokens (ink/canvas/line/link/accent-soft…), which already flip with `[data-theme]`/OS preference; one :root mapping themes both modes. Gem stylesheet link moved ABOVE the `:app` tag so the app-side :root overrides win the cascade (the :app tag itself untouched).
- New tokens in 01-tokens.css (light + dark + OS-fallback blocks): `--fill-subtle` (code bg / quiet hovers) and `--code-*` syntax palette (GitHub light/dark). Also mapped Lexxy font → `--font-body`, radius → `--radius-ui`. Left as-is: `--highlight-*` author text-highlights and fixed functional red/green/blue/purple.
- Verified served CSS: link order gem→tokens→bridge, 24 `--lexxy-*` remaps and dark `--code-*` present in the served assets. Visual dark-mode pass in a browser still worth an eyeball.
- refs: lexxy-theme.css, 01-tokens.css, layouts/application.html.erb

## [2026-07-03] fix | Publish route → /posts/:id/publish (Fizzy naming)
- Renamed `resource :publication` → `resource :publish` (Posts::PublishesController) to match the house style Fizzy/Basecamp use (`resource :publish` nested under the item — still a resource with create/destroy, not a custom member action). Per user correction.
- refs: config/routes.rb, app/controllers/posts/publishes_controller.rb, posts/show.html.erb, posts_controller_test.rb

## [2026-07-03] build | Record/Recordable spine + Post recordable (Lexxy)
- Implemented the delegated-type content spine per ADR 0006: `records` (recordable pointer, creator → users, self-ref parent, position, trashed_at) + `Record` model (delegated_type, creator defaults to Current.user, children, trash/restore), `Recordable` concern (has_one :record, delegates creator/trash), and first recordable `Post` (title, drafted/published enum à la Fizzy `Card::Statuses`, published_at stamped on first publish only, pinned_at). Spine is deliberately tenant-agnostic — no account_id; Alcovo adds scoping later.
- Installed Action Text + Active Storage; replaced Trix with **Lexxy** (gem 0.9.22, adapter mode on edge Rails: `form.rich_textarea` → `<lexxy-editor>`; importmap pin, layout stylesheet link, content wrapper class trix-content → lexxy-content, deleted actiontext.css).
- Posts CRUD on the existing components: index (perma-header + `.list`, feed order = pinned first then newest published), show (canvas head + editable title now *persisting* via an enclosing PATCH form — editable_controller submits `input.form` and guards blur-after-Enter), new/edit (field.css + Lexxy body), destroy → `record.trash` (recoverable; purge job deferred), publish/unpublish as `resource :publication`.
- Tests: model (envelope autosave, trash/restore, cascade destroy, threading, unique envelope; publish-date preservation, feed order) + controller (CRUD, trash hides/404s, publication, Lexxy renders, auth). Setup-flow tests now `simulate_fresh_install` (records FK ← users). 40 runs green; rubocop clean; smoke-tested Lexxy assets through Propshaft (@import rewriting OK).
- pages touched: [[0006-record-recordable-generic-spine]], [[overview]], [[index]]
- refs: db/migrate/20260703000001-2, app/models/record.rb, app/models/concerns/recordable.rb, app/models/post.rb, app/controllers/posts_controller.rb, app/controllers/posts/publications_controller.rb, app/views/posts/*, editable_controller.js, config/importmap.rb, config/routes.rb, Gemfile (lexxy)

## [2026-07-02] tweak | --brand-text token (teal, 7:1) for the list byline
- Added mode-aware `--brand-text` (teal-tinted body text, 7:1 on the canvas: dark teal light / light teal dark). List byline (name · date) now uses it instead of neutral --ink-muted.
- refs: 01-tokens.css, list.css

## [2026-07-02] tweak | List view gets the standard canvas head too
- Added `shared/canvas_head` (breadcrumb Alcovo / Message Board + ⋯) atop list-view with board-level menu items (Subscribe / Manage categories / Board settings). Both list + item views now use the standard head.
- refs: static/list_view.html.erb

## [2026-07-02] refactor | Standard canvas head (breadcrumb + context menu) as a partial
- Extracted the theme's inline `.canvas__head` into `shared/_canvas_head` (breadcrumb from a `crumbs` local + ⋯ popover shell that YIELDS the menu items — structure standard, contents context-specific). Theme + item-view both render it; deleted the old `shared/_context_menu`. Item-view wraps head + perma-header in the `editable` controller so the menu's Rename (and clicking the title) drive the editable title; removed the perma-header's separate ⋯ menu.
- pages touched: [[app-shell]]
- refs: shared/_canvas_head.html.erb, static/theme.html.erb, static/item_view.html.erb

## [2026-07-02] build | perma-header + list-view/item-view composition pages
- Added `.perma-header` (page title + toolbar), adapted from Basecamp's MessageBoardHeader to Alcovo tokens (teal not blue, reuses our button/popover/menu). Supporting components: `button-group.css` (segmented control), `filter-by-text.css` (overlapping label + kbd via :placeholder-shown), `kbd.css`, `editable.css` + `editable_controller.js` (click-to-edit title). Category/sort dropdowns reuse the `.menu` popover; taught `anchored-popover` a `placement` value (below | top) so dropdowns open below the trigger while the canvas ⋯ keeps top; added `.menu__check` for single-select.
- New pages: `static#list_view` (/list-view) = perma-header toolbar + `.list` of messages; `static#item_view` (/item-view) = editable title (click or context-menu Rename) + content. Routes + StaticController actions added.
- Static-checked (routes syntax, braces, no baked colors, files present); interactive bits (dropdown placement, editable, tabs) not server-run per request — need a browser click.
- pages touched: [[app-shell]]
- refs: perma-header.css, button-group.css, filter-by-text.css, kbd.css, editable.css, menu.css, editable_controller.js, anchored_popover_controller.js, shared/_context_menu.html.erb, static_controller.rb, config/routes.rb, static/list_view.html.erb, static/item_view.html.erb

## [2026-07-02] build | Tier 1 components + Tabs (forms, modal, pagination, empty)
- Forms: expanded `field.css` (select w/ chevron, textarea, input-group affixes, sizes, disabled, `--required`, `field__error`; fixed its baked danger reds → `--danger-ink`); added `choice.css` (checkbox/radio via accent-color), `switch.css` (toggle), `error-summary.css` + `shared/_error_summary` partial (Rails model.errors).
- `modal.css` + `dialog_controller.js` — native <dialog> modal (Esc + backdrop-click close, animated). Added `--scrim` token; repointed the menu bottom-sheet backdrop to it. `pagination.css` (current page = teal-800/white AAA). `empty.css` (blank slate). `tabs.css` + `tabs_controller.js` (ARIA tabs, click + arrow-key).
- Also tokenized toast.css border colors (removed last baked component colors; only vendored open-props remains). Added all to the styleguide. Static-checked (braces, tokens exist, no baked colors, icons/controllers present); not server-run per request — the JS bits (dialog, tabs) use standard Stimulus wiring.
- pages touched: [[app-shell]]
- refs: field.css, choice.css, switch.css, error-summary.css, modal.css, pagination.css, empty.css, tabs.css, dialog_controller.js, tabs_controller.js, toast.css, 01-tokens.css, shared/_error_summary.html.erb, static/theme.html.erb

## [2026-07-02] build | u-gap utilities + u-margin styleguide demo
- Added `u-gap.css` (gap/half/double/0 + row/col single-axis, --u-pad scale). Added a `.u-margin` family demo to the styleguide Spacing section (bordered flow-root container so margin space is visible and doesn't collapse). Pad utilities left unchanged per request.
- pages touched: [[app-shell]]
- refs: u-gap.css, static/theme.html.erb

## [2026-07-02] fix | Primary button → solid teal-800 + white (AAA at rest)
- Reverted the AA-at-rest teal-500 + dark-text primary (read as low-contrast, same-hue). Now solid teal-800 (`--brand-strong`) + white = 7.6:1 AAA at rest, darken-on-hover. (Note: white on the light teal-500 was only 2.49:1 — white needs the darker teal.)
- refs: button.css

## [2026-07-02] tweak | Primary button AA→AAA-on-hover; u-margin utilities
- Primary button is now a vibrant teal-500 fill + teal-950 text (5.97:1, AA) at rest, deepening to teal-800 + white (7.6:1, AAA) on hover — a deliberate AA-at-rest exception for the CTA (WCAG judges the resting state; hover enhances). Removed the now-unused --accent-pale token.
- Added `u-margin.css`: margin utilities mirroring u-pad (all/block/inline, half/double/0) plus single logical edges (block-start/-end, inline-start/-end each half/double) and auto variants (u-margin-inline-auto etc.).
- pages touched: [[app-shell]]
- refs: button.css, 01-tokens.css, u-margin.css

## [2026-07-02] a11y | Component labels to AAA 7:1 (token-driven, never baked)
- Audited every text/fill pair (both modes) and raised component labels to ≥7:1, all via new tokens in 01-tokens.css (no baked values): `--link` (mode-aware dark/light teal; links now underlined since dark), `--ink-on-soft` (avatar initials + accent badge, mode-aware, replaces --badge-accent-ink/--avatar-ink), `--menu-context-bg` retuned (teal-800 light / teal-400 dark), and semantic `--success/warning/danger-surface` + `-ink` + `--danger-solid`. Badge/alert/button-danger now reference these; danger button became a soft-fill (light-red, AAA in both modes) like the primary. Brand link neutralized to --ink (no underline). Muted metadata (byline/placeholder/table-head) intentionally left at AA — 7:1 defeats "muted". Solved OKLCH lightnesses numerically; re-audited: all pairs 7.09–7.60 in light + dark. HTTP 200, tokens served.
- pages touched: [[theme-background-colors]]
- refs: 01-tokens.css, badge.css, alert.css, button.css, avatar.css, list.css, 02-base.css, bar.css

## [2026-07-02] tweak | List: white count text + whole-row click-through (verified)
- Count bubble now teal-700 (`--brand-muted`) + white text (5.48:1; white on the old teal-500 was ~2.5:1). Whole row clicks through via a stretched-link `.list__body::after` (item is position:relative) plus `pointer-events:none` on the count so it doesn't capture its own clicks. Verified headless: avatar/title/excerpt/count all resolve to the row link.
- pages touched: [[app-shell]]
- refs: list.css

## [2026-07-02] build | Generic .list / .list__item (summary rows), verified
- Added a generic list component (Basecamp's article-list, adapted to Alcovo tokens/BEM — not React/Tailwind). `list.css`: avatar + linked title/meta + optional trailing count; single hairline dividers (row border-top + list border-bottom, no doubling); title ellipsis, meta 2-line clamp; reuses `.avatar` (56px) and `.badge--warning` (eye icon) for the "client visible" pill; count bubble uses `--accent`/`--accent-ink` (teal, not Basecamp blue). Partial `shared/_list_item` with strict locals (href/title/author/date/excerpt/avatar_src/avatar_alt/client_visible/comment_count). Added a List section to the styleguide. Verified headless: title truncates, count sits OUTSIDE the anchor, client badge renders.
- pages touched: [[app-shell]]
- refs: list.css, shared/_list_item.html.erb, static/theme.html.erb

- The theme and tint Stimulus controllers now write a year-long cookie (`theme`, `tint`; path=/, samesite=lax) on change. ApplicationController exposes `current_theme` (whitelisted) and `current_tint` (sanitized) helpers; the layout renders `<html data-theme data-tint>` from them, so the persisted appearance is applied server-side on first paint (no FOUC — chosen over localStorage for that reason). Verified headless: set dark/olive → full reload → server renders dark/olive, labels sync.
- pages touched: [[app-shell]]
- refs: application_controller.rb, application.html.erb, theme_controller.js, tint_controller.js

## [2026-07-02] fix | Canvas max-width was 1.6× too wide (rem/px unit mismatch); remove stone
- The canvas dims were authored as if 1rem=10px (comments said 1088px/48px/40px) but the app uses a 16px root, so max-width:108.8rem was actually 1740px — hence "too wide" on big monitors. Corrected to the intended px: max-width 68rem (1088px), gutter calc(100% - 3rem), padding-inline 2.5rem, and the head's mirrored margin-inline -2.5rem. Verified: 1088px cap on a 2560px viewport.
- Removed the `stone` tint (redundant with taupe — ΔE 0.0024, ~8× below JND) from tokens, cycler, styleguide, and doc.
- pages touched: [[app-shell]], [[theme-background-colors]]
- refs: canvas.css, menu.css, 01-tokens.css, _header.html.erb, static/theme.html.erb

## [2026-07-02] decision | Tints promoted to -200 (the -100 vs -200 test picked -200)
- The styleguide A/B confirmed -200 reads better than -100, so the six base tint names (olive/taupe/mauve/mist/zinc/stone) now hold the Tailwind -200 values; removed the separate `*-200` experiment tokens, the styleguide's second swatch row, and the -200 cycler entries. `--neutral-bg` fallback → zinc-200. Doc updated.
- pages touched: [[theme-background-colors]], [[app-shell]]
- refs: 01-tokens.css, _header.html.erb, static/theme.html.erb

## [2026-07-02] build | User-menu theme+tint row; mode-aware badge/avatar; stone; -200 test
- User menu: theme (light/dark/auto) and tint (color) toggles now share a `.menu__row` (flexbox + gap) above Sign out; the tint control moved out of the fixed bottom-right dropper into the menu (tint controller now updates a title-cased label, flash removed). Removed the styleguide's floating dropper + its CSS.
- Accent badge fg is now mode-aware `--badge-accent-ink` (teal-600 light 3.33:1 / teal-400 dark 4.97:1) since the soft fill flips light↔dark; the dark-mode avatar uses the same value (`--avatar-ink`), matching the badge (4.97:1). Light avatar stays teal-700.
- Added `stone` tint (stone-100) to the tints, cycler, and styleguide.
- Added a `-200` test set for all six tints (tokens + a second styleguide swatch row + appended to the cycler) to judge whether more color is too much.
- pages touched: [[app-shell]], [[theme-background-colors]]
- refs: 01-tokens.css, menu.css, badge.css, avatar.css, tint_controller.js, theme_controller.js, _header.html.erb, static/theme.html.erb

## [2026-07-02] tweak | Context menu dark-mode bg up a level (teal-400 → teal-500)
- Dark-mode `--menu-context-bg` bumped one level darker to teal-500 (= var(--brand)). Text stays teal-950; contrast 5.83:1 (AA). Light mode unchanged (teal-700).
- pages touched: [[app-shell]]
- refs: 01-tokens.css

## [2026-07-02] build | Light/dark/auto toggle in the user menu (verified)
- Added a cycling theme control as a `.menu__item` above Sign out in the user menu. `theme_controller.js` cycles `<html data-theme>` light → dark → auto on click; label + sun/moon/monitor icon reflect the mode (icon swap via `.theme-toggle[data-mode]` in theme-toggle.css). "auto" falls through to the existing prefers-color-scheme query. No persistence yet (resets to light on reload, like the tint dropper). Verified headless: cycles correctly, label/icon track, menu stays open.
- pages touched: [[app-shell]]
- refs: theme_controller.js, theme-toggle.css, app/views/layouts/_header.html.erb

## [2026-07-02] tweak | Context menu reveals from the canvas right edge (not page)
- The `translate: 100%` slide dragged the panel in from off-screen through the canvas→viewport gutter, reading as "from page right." Swapped to a `clip-path: inset(0 0 0 100%)` → `inset(0)` reveal (added clip-path to the .menu transition), so it wipes in from its own right edge while pinned at the canvas edge. Verified headless: opens fully revealed (clip-path inset(0px)), flush right, closes.
- pages touched: [[app-shell]]
- refs: menu.css

## [2026-07-02] tweak | Context menu goes dark teal (teal-700 light / teal-400 dark)
- Deliberately-odd: `.menu--context` background is teal-700 (light mode, near-white text) inverting to teal-400 (dark mode, teal-950 text) via `--menu-context-bg/-ink` tokens. Close/items/hover/separator recolor to stay legible. Contrast checked: 5.20:1 light, 7.59:1 dark (both pass AA).
- pages touched: [[app-shell]]
- refs: 01-tokens.css, menu.css

## [2026-07-02] tweak | Context menu: trim top pad; track toggle on scroll (verified)
- Reduced `.menu--context` padding-block-start 3rem → 2.5rem (item still clears the close, 2px gap). The anchored-popover controller now re-aligns the open menu to the toggle on scroll/resize, so it tracks the sticky header instead of detaching. Verified headless: pre-scroll menuTop=toggleTop=70; post-900px-scroll menuTop=toggleTop=headTop=0.
- pages touched: [[app-shell]]
- refs: menu.css, anchored_popover_controller.js

## [2026-07-02] build | Context menu: internal close, flush-right, sticky head (verified)
- Reworked the context menu: close (X) moved INSIDE the popover (same top layer, so z-index lifts it above the items — an external button can't beat the top layer), same `button--icon button--ghost` shape as the ⋯ toggle, menu padded down to clear it. Menu now sits at the top of the canvas, flush to the right edge (controller aligns popover top/right to the toggle). Menu font dropped to `--font-size-0` (matches breadcrumb). Made `.canvas__head` `position: sticky; top: 0` (removed the canvas `overflow: clip` that would have disabled sticky; head gets a background + matching top radius). Moved `.menu--context` into menu.css so it loads after the base `.menu` (a cascade bug where the base padding shorthand overrode the modifier). Verified headless: item-clears-close ✓, same shape (38×38) ✓, flush right (1227=1227) ✓, sticky after 900px scroll (top=0) ✓, X closes ✓.
- pages touched: [[app-shell]]
- refs: menu.css, canvas.css, anchored_popover_controller.js, shared/_context_menu.html.erb, app/views/static/theme.html.erb

## [2026-07-02] fix | Context menu positioned below toggle (verified headless)
- A top-layer popover can't be z-indexed under the toggle, so the menu must sit below it. First attempt (CSS anchor positioning) silently failed in-browser — popover fell to top-left, and the `@supports not(anchor-name)` fallback didn't trigger because `anchor-name` parses. Replaced with an `anchored-popover` Stimulus controller that sets the popover inset from the toggle's rect on `beforetoggle` (uses `documentElement.clientWidth` to avoid a scrollbar over-offset). Verified via headless Chromium: opens below the toggle, right edges aligned (719=719), ⋯→X swap shows, second click closes.
- pages touched: [[app-shell]]
- refs: canvas.css, anchored_popover_controller.js, shared/_context_menu.html.erb

## [2026-07-02] build | Context toggle X-swap; soft-teal primary; avatar contrast
- Context-menu toggle now sits flush right and swaps ⋯ → X (via `:has(~ .menu--context:popover-open)`) so the same button (pixel-identical) opens/closes without moving the mouse; still native Popover API. Primary button is now a soft fill: `--accent-pale` (brand teal at teal-50 brightness) with teal-500 border + teal-950 text. Avatars bumped their initials to `--brand-muted` (teal-700) for contrast on the soft fill.
- pages touched: [[theme-background-colors]]
- refs: canvas.css, button.css, avatar.css, 01-tokens.css, app/views/static/theme.html.erb

## [2026-07-02] build | Data table component; canvas head hugs border; side context menu
- Added a `.table` data-table component (table.css, +zebra, right-align cells, scroll wrapper) and a Data tables section in the theme. Made `.canvas__head` full-bleed hugging the top border (canvas gets `overflow: clip`; head has no block padding, 2rem inline). Extracted the context menu to a stub partial `shared/_context_menu` and reworked it to slide in from the canvas's right side — still native Popover API (no JS). Moved the tint drip earlier to a small fixed bottom-right widget.
- pages touched: [[app-shell]]
- refs: table.css, canvas.css, menu.css, shared/_context_menu.html.erb, app/views/static/theme.html.erb

## [2026-07-02] build | Canvas head (breadcrumb + context menu); drip floats bottom-right
- Renamed `.main-content` → `.canvas` (canvas.css) and dropped its roundness one level (radius-3 → radius-2). Added `.canvas__head` — a thin top strip with a `.breadcrumb` (new breadcrumb.css) left and a `.menu--context` (⋯) popover right, positioned via CSS anchor positioning with a fixed fallback. Moved the styleguide tint drip to a smaller, fixed, floating bottom-right widget. Added to the theme page.
- pages touched: [[app-shell]]
- refs: canvas.css, breadcrumb.css, 02-base.css, app/views/static/theme.html.erb, app/views/layouts/application.html.erb

## [2026-07-02] build | App-shell chrome — header top-right, PWA, toasts, Native gate
- Implemented ADR 0004/0005: moved the user-menu avatar + a notification bell to the header top-right and removed the footer; made the `.menu` popover responsive (desktop dropdown / mobile bottom-sheet at 48rem breakpoint); enabled the PWA (manifest link, `pwa` routes, SW registration, real manifest colors); added `hotwire_native?` + `hotwire-native` body-class gate (`hotwire-native.css` hides `.app-header`/`.app-tabbar`); added a `.toasts` aria-live region rendering flash with a `toast` auto-dismiss controller. Bell is a stub; bottom tab bar still deferred (no nav destinations). Not server-verified per request (Ruby syntax + manifest JSON checked).
- pages touched: [[app-shell]]
- refs: _header.html.erb, _toasts.html.erb, application.html.erb, menu.css, toast.css, hotwire-native.css, toast_controller.js, application_controller.rb, config/routes.rb, app/views/pwa/manifest.json.erb

## [2026-07-02] decision | Mobile — Hotwire Native target, PWA in development
- Resolved ADR 0004's open mobile sub-decision: production target is Hotwire Native (native tab bar/nav), but development assumes a responsive PWA. So we DO build responsive mobile web chrome, gated under a `hotwire-native` body class so native nav takes over in the wrapper. Content responsive on all surfaces. Near-term task: enable the disabled PWA scaffolding.
- pages touched: [[0005-mobile-hotwire-native-pwa-dev]], [[0004-top-bar-app-shell]], [[app-shell]], [[index]]
- refs: app/views/pwa/manifest.json.erb, app/views/pwa/service-worker.js

## [2026-07-02] decision | Top-bar app shell; mobile nav fork left open
- Chose a top-bar app shell with profile + notification bell top-right (retiring the bottom-left footer avatar), over a left-sidebar shell. Documented desktop/mobile placement, notifications (bell top-right / slim mobile header), and toasts (bottom-right desktop / top banner mobile). Flagged the open sub-decision: responsive-web mobile chrome vs Hotwire Native (native tab bar) — web stays responsive either way. Documentation only; no UI built yet.
- pages touched: [[0004-top-bar-app-shell]], [[app-shell]], [[index]]
- refs: app/views/layouts/_header.html.erb, _footer.html.erb

## [2026-07-02] note | Theme background colors
- Documented site/canvas backgrounds (light + dark) and the rotating light-mode account tints, each mapped to its best-fit Tailwind class. Green and orange deliberately diverge from the nearest-distance class to preserve hue intent. Dark-mode canvas pinned (`gray-800`); light-mode canvas left as an open question.
- Added precise OKLCH tint tokens (two forms: Tailwind-v4 relative-color-syntax, and raw OKLCH). Alcovo ships the raw OKLCH form since there's no Tailwind. Green needs a 62% chroma cut; the rest are rounding errors.
- pages touched: [[theme-background-colors]], [[index]]
- refs: concepts/theme-background-colors.md

## [2026-07-01] decision | Collapse wiki into docs/
- Merged the `wiki/` machinery into `docs/` as the single documentation folder; kept the CLAUDE.md contract, index, log, decisions, templates, and raw/. Registered the design docs in the index. Retired the `wiki/` folder.
- pages touched: [[0003-collapse-wiki-into-docs]], [[0001-adopt-work-tracking-wiki]], [[index]], [[overview]], [[CLAUDE]]
- refs: docs/

## [2026-07-01] refactor | Reconcile docs to Person / User / Account
- Swept the design docs to the new vocabulary (ADR 0002): rewrote data-model.md, schema.rb, and account-creation-concern.md (renamed from group-creation-concern.md); fixed the Alcovo-facing mapping tables/prose in both Fizzy docs (verbatim Fizzy source left intact). Renamed placeholder "Writer Group" → "Alcovo" throughout.
- pages touched: [[0002-domain-vocabulary-person-user-account]]
- refs: data-model.md, schema.rb, account-creation-concern.md, fizzy-authentication.md, fizzy-user-account-model.md

## [2026-07-01] decision | Domain vocabulary: Person / User / Account
- Chose plain names for the three core models: keep Fizzy's `User`/`Account`, rename `Identity` → `Person`. Retired `Membership`, `Group`, `bucket`.
- pages touched: [[0002-domain-vocabulary-person-user-account]], [[domain-vocabulary]], [[index]], [[overview]]
- refs: data-model.md, fizzy-authentication.md

## [2026-07-01] note | Executive summary of docs research
- Alcovo is a multi-tenant "writer group" app modeled on Basecamp's Fizzy — delegated-type content spine, passwordless identity-centric auth, shared-DB row-level tenancy, Lexxy/Action Text rich text, MariaDB+HA for SaaS. Key open decision: shared multi-tenant SaaS vs. per-customer self-hosted.
- refs: (all reference docs)

## [2026-07-01] decision | Adopt a work-tracking wiki
- Established a Karpathy-style, LLM-maintained work log + knowledge base (initially in `wiki/`; later merged into `docs/` — see [[0003-collapse-wiki-into-docs]]).
- pages touched: [[0001-adopt-work-tracking-wiki]], [[index]], [[overview]]
- refs: CLAUDE.md
