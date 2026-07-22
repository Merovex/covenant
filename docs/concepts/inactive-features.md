---
type: concept
title: Inactive features — present in code, hidden from the UI
status: active
tags: [support-desk, navigation, posts, forum, chatroom, dormant]
created: 2026-07-22
updated: 2026-07-22
sources: [support-desk-plan.md]
---

# Inactive features — present in code, hidden from the UI

Covenant is a **support desk** ([[support-desk-plan]]), but it was scaffolded from
the Alcovo template, which shipped a blog, a forum, and a chatroom. Those tools
still exist in full — models, controllers, routes, views, tests all pass — but
they are **hidden from navigation** so the app presents purely as a support desk.

They were **hidden, not deleted**: the code is battle-tested, it's the reference
implementation of the Record/Recordable spine ([0006](../decisions/0006-record-recordable-generic-spine.md)/[0007](../decisions/0007-versioned-recordables.md))
that Licenses/Tickets/Replies are modelled on, and a future Covenant tool may want
one of them back. Deleting would throw away working, exemplary code for no gain.

## What's dormant

| Feature | Routes (still live) | Recordable | Notes |
|---------|--------------------|-----------|-------|
| **Posts** (blog) | `resources :posts` (+ drafts, publish, pin, events, changes, versions, comments) | `Post` (Publishable) | The canonical Publishable example. |
| **Forum** (message board) | `resources :messages, path: "forum"` (+ same sub-resources) | `Message` (Publishable) | One board per install. |
| **Categories** | `resources :categories` | plain table | Forum vocabulary — orphaned while the forum is hidden. |
| **Chatroom** | `resource :chatroom`, `resources :chat_lines` | `ChatLine` (Recordable) | Single install-wide room. |
| **Comments** | `resources :comments` (nested under posts/messages) | `Comment` (Recordable) | Threading model that `Ticket#replies` mirrors. |

## How they were hidden

Only the **entry points** were removed — no controller, model, route, or view
was touched:

- **App menu** (`app/views/layouts/_app_menu.html.erb`) — dropped the Posts /
  Forum / Chatroom quick-cards and "Go to" links (and the Categories link and
  the Post/Message "Recent" list). The menu now lists only the support desk.
- **Dashboard** (`app/controllers/dashboard_controller.rb`,
  `app/views/dashboard/show.html.erb`) — root is the support-desk dashboard, not
  a hub linking to these sections.
- **Root route** — was `static#theme`, now `dashboard#show`.

The URLs still resolve if typed directly (e.g. `/posts`), gated by the same
`domain_admin` / auth rules as before — they're just not linked anywhere.

## Bringing one back

Re-add its link(s) to the app menu (and/or a dashboard tile). Nothing else is
required; the feature is intact. If a section is being **permanently** retired
instead, remove its routes/controllers/models/views/tests as a deliberate
deletion and record it in an ADR — don't leave half-wired dead code.
