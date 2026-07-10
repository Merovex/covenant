---
type: concept
title: App menu — the Basecamp-style jump menu
status: active
tags: [hotwire, stimulus, navigation, popover]
created: 2026-07-10
updated: 2026-07-10
sources: []
---

# App menu — the Basecamp-style jump menu

## Summary
Alcovo's global navigation: a centered "Alcovo ⌄" trigger in the top bar opens a
command-palette sheet with a quick-nav card grid, a type-to-filter jump search,
secondary destinations, and recent records. Distinct from the per-record
**context menu** (`.menu--context`, "what do I do here"); this is "where do I go."
Ported from the sibling Inkwell app and trimmed to Alcovo's routes.

## Details
Three load-bearing primitives (over [[app-shell]] / [0004](../decisions/0004-top-bar-app-shell.md)):

1. **Disclosure-as-dialog** — the trigger is a `popovertarget` button; the sheet
   is a native Popover (`role="dialog"`), which gives Esc + click-outside dismiss,
   top-layer rendering, and a `::backdrop` scrim (the `--scrim` token) for free.
   Positioned `1em` from the top.
2. **Server-rendered content** — `layouts/_app_menu.html.erb` + `AppMenuHelper`:
   a card grid (Posts/Forum/Chatroom), a "Go to" list (Posts/Forum/Chatroom, plus
   Categories for `domain_admin?` users only — matching the CategoriesController
   `authorize!`), and Recent records (last-touched Posts + Messages, each with a
   type icon + badge). Home is a house icon in the header-left.
3. **Type-to-filter** — the `app-menu` Stimulus controller filters the rendered
   rows live, hides empty groups, and supports ↑/↓/Enter; the search autofocuses
   on open.

Recents come from `Record.recently_active` (added with this work) limited to the
`MENU_RECORDABLES` that have a standalone page (`Post`, `Message`); links use the
`Record` id, matching the app's id-first routing.

Refs: `../../app/views/layouts/_app_menu.html.erb`,
`../../app/views/layouts/_header.html.erb`,
`../../app/javascript/controllers/app_menu_controller.js`,
`../../app/helpers/app_menu_helper.rb`,
`../../app/assets/stylesheets/app-menu.css`, `../../app/models/record.rb`.

## Gotchas / open questions
- Dropped from Inkwell as irrelevant here: Books, Series, Authors, Subscribers,
  Broadcasts, Analytics, System settings (no such routes/models in Alcovo).
- Categories is gated to `domain_admin?`. Open call: show it to everyone and let
  the policy 404 non-admins instead.
- Not yet (the Basecamp "polish" tier): a true focus-trap (native popover lets
  Tab escape), a lazy/prefetched `turbo-permanent` frame (currently rendered
  inline each page), remote search beyond loaded rows, a global open hotkey,
  favorites/stars, per-item hotkeys.
