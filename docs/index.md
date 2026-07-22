# Documentation Index

Catalog of everything in `docs/`. Keep this in sync whenever a page is added,
renamed, or superseded. See [[CLAUDE]] (`CLAUDE.md`) for conventions.

- **[overview.md](overview.md)** — living synthesis of the current project state
- **[log.md](log.md)** — chronological work log (append-only)

## Reference & design docs

Polished research/design (modeled on Basecamp's Fizzy). See [[domain-vocabulary]]
for canonical naming.

- [data-model.md](data-model.md) — delegated-type (`Recording`/`Recordable`) content model
- [schema.rb](schema.rb) — notional Rails schema for the data model
- [account-creation-concern.md](account-creation-concern.md) — `Account::Foundable` + `Signup` flow
- [fizzy-authentication.md](fizzy-authentication.md) — Fizzy's passwordless auth protocol
- [fizzy-user-account-model.md](fizzy-user-account-model.md) — Fizzy's User / Account / Access layer
- [multi-tenancy.md](multi-tenancy.md) — shared-DB, row-level tenancy (`Current.account`)
- [database-and-scaling.md](database-and-scaling.md) — SQLite vs MariaDB; when to split app servers
- [lexxy-and-active-record.md](lexxy-and-active-record.md) — Lexxy editor + Action Text coupling
- [ses-migration-runbook.md](ses-migration-runbook.md) — Phase 0 (AWS + DNS) checklist for the SES/SNS email setup (ADR 0008); ported verbatim from Inkwell, Inkwell naming intact
- [support-desk-plan.md](support-desk-plan.md) — self-contained build plan for License tracking + Ticket management (Customer/License/Ticket/Reply on the spine; inbound/outbound email; Pine theme); anchors ADRs 0009 & 0010

## Decisions (ADRs)

| # | Title | Status | Date |
|---|-------|--------|------|
| [0001](decisions/0001-adopt-work-tracking-wiki.md) | Adopt a work-tracking wiki | superseded → 0003 | 2026-07-01 |
| [0002](decisions/0002-domain-vocabulary-person-user-account.md) | Domain vocabulary — Person / User / Account | accepted | 2026-07-01 |
| [0003](decisions/0003-collapse-wiki-into-docs.md) | Collapse documentation into a single docs/ folder | accepted | 2026-07-01 |
| [0004](decisions/0004-top-bar-app-shell.md) | Top-bar app shell — profile & notifications top-right | accepted | 2026-07-02 |
| [0005](decisions/0005-mobile-hotwire-native-pwa-dev.md) | Mobile — Hotwire Native target, PWA in development | accepted | 2026-07-02 |
| [0006](decisions/0006-record-recordable-generic-spine.md) | Record/Recordable — generic, tenant-agnostic content spine | accepted | 2026-07-03 |
| [0007](decisions/0007-versioned-recordables.md) | Versioned recordables — event-tagged immutable versions | accepted | 2026-07-03 |
| [0008](decisions/0008-email-relay-amazon-ses.md) | Email relay — adopt Amazon SES/SNS | accepted | 2026-07-10 |
| [0009](decisions/0009-support-desk-customers-licenses-tickets.md) | Support desk — Customers, Licenses, Tickets, Replies | accepted | 2026-07-22 |
| [0010](decisions/0010-inbound-email-action-mailbox-ses.md) | Inbound support email — Action Mailbox (SES/SNS) + Message-ID token routing | accepted | 2026-07-22 |

## Concepts

- [domain-vocabulary](concepts/domain-vocabulary.md) — canonical names: Person / User / Account
- [theme-background-colors](concepts/theme-background-colors.md) — site/canvas backgrounds + rotating light-mode tints → Tailwind classes
- [theme-model-playbook](concepts/theme-model-playbook.md) — the three appearance axes (mode / tint / accent) + how-to steps to change each
- [app-shell](concepts/app-shell.md) — top-bar shell; responsive nav; the responsive-web vs Hotwire Native mobile fork
- [css-architecture](concepts/css-architecture.md) — CUBE/BEM hybrid: layers, u- compositions/utilities, standard BEM blocks, exceptions via modifiers/data-attrs
- [app-menu](concepts/app-menu.md) — the Basecamp-style jump menu (native popover + type-to-filter), ported from Inkwell

## Entities

_None yet. Create from `_templates/entity.md` → `entities/<slug>.md`._

## Summaries

_None yet. Create from `_templates/summary.md` → `summaries/<slug>.md`._
