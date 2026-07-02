# Writer Group — Notional Data Model

*A first-pass data model for an author writer-group site, modeled on the
Basecamp **delegated-type** (`Record`/`Recordable`) pattern. This is
**notional** — a thinking document, not a migration. Column names are idiomatic
Rails guesses; anything I'm inferring rather than certain of is flagged.*

Companion file: [`schema.rb`](./schema.rb) — the same model expressed as a
notional Rails `schema.rb`.

---

## 1. What we're modeling

A private community of authors runs its work inside a shared space. Members
post to topic **boards**, keep durable **documents**, answer a recurring
**check-in question** each week, and chat in a lightweight back-channel. The
site needs to treat all of that heterogeneous content uniformly — scope it to a
group, attribute it to a person, let it be commented on, trashed, and listed on
a timeline — without duplicating that plumbing per content type.

That is exactly the problem Basecamp's **delegated types** solve, so we adopt
the same spine.

---

## 2. The spine: `Recording` + `Recordable`

One shared **`Recording`** row wraps every piece of content and holds the common
envelope. A **recordable** row (`Message`, `Document`, `Question`, `Answer`,
`Comment`, `Upload`) holds only what's specific to that type. One-to-one between
them via a polymorphic pointer.

```
recordings                              messages / documents / questions / answers / ...
┌─────────────────────────┐            ┌────────────────────────────┐
│ id                      │            │ id                         │
│ recordable_type ────────┼───────────▶│ (type-specific columns)    │
│ recordable_id           │  1  ──  1  │                            │
│ bucket_id   (the group) │            └────────────────────────────┘
│ creator_id  (Person)    │
│ parent_id   (self-ref)  │◀── comments & answers point back here
│ status                  │
│ position                │
│ visible_to_members …    │
│ timestamps              │
└─────────────────────────┘
```

**Why this and not the alternatives**

- **STI (one wide table):** every type shares one sparse table full of nulls.
  Columns explode; every new field touches all types.
- **Plain polymorphic + duplication:** each type re-declares `creator`,
  `status`, `group`, comments… behavior drifts apart over time.
- **Delegated type (chosen):** shared behavior written **once** on `Recording`;
  type-specific data isolated per table. New content type = new small table +
  `include Recordable`.

**Load-bearing facts about the spine**

- `recordable_type` / `recordable_id` is the delegated-type join to the specific
  row.
- **`bucket`** is our word for the container a member works in — here, an author
  **Group** (Basecamp calls it a "bucket"; we keep the name internally to match
  the pattern, expose it as *Group* in the UI).
- **`parent_id` is self-referential on `Recording`.** A comment is just a
  Recording whose `recordable` is a `Comment` and whose `parent` is the
  Recording being commented on. Same mechanism scopes a check-in **Answer** to
  its **Question**. This is why *anything* is commentable with zero per-type work.
- **Body text is not a column.** Rich content is **Action Text**
  (`action_text_rich_texts`, polymorphic to the recordable) with attachments via
  **Active Storage**. Keeps the recordable tables thin.

---

## 3. Containers (the "dock")

A **Group** (`bucket`) enables a set of tools. Each tool is a container that
recordings hang off of. For the four content types in scope:

| Container         | Holds            | Recordable it parents |
|-------------------|------------------|-----------------------|
| `Message::Board`  | Messages         | `Message`             |
| `Vault`           | Documents, files | `Document`, `Upload`  |
| `Questionnaire`   | Questions        | `Question`            |
| `Chat`            | Chat lines       | `Chat::Line` (*not* a recording — see §5) |

A group can have **several boards** (e.g. a "Workshop" board, a "Kickoffs"
board, a "Heartbeats" board) — the board is itself a lightweight record scoped
to the bucket.

---

## 4. The content types

### Message (recordable)
A post to a board. Thin table; body is Action Text.

- `subject` — the title
- `content` → Action Text (rich body)
- parent = the `Message::Board` (via its Recording)
- commentable (comments are child Recordings)

### Document (recordable)
A durable reference doc living in a Vault.

- `title`
- `content` → Action Text
- parent = the `Vault`
- commentable

### Question (recordable) + Answer (recordable)
The recurring check-in. **Two delegated types** working together.

- `Question`: `title` (the prompt, e.g. *"What did you knock out last week?
  What's next?"*), plus a recurring **schedule** — `frequency`
  (`every_week`, `every_day`, …), `days` mask, `time_of_day`. Lives in a
  `Questionnaire`.
- `Answer` (`Question::Answer`): one Recording per member per period.
  `content` → Action Text; `group_on` (the date/week the answer belongs to);
  parent = the `Question` (via its Recording). Commentable.

This is the highest-volume interactive surface in the reference project (171
answers to a single weekly question), so the Answer table is expected to be the
busiest recordable.

### Comment (recordable)
Not a top-level type but part of the spine. A Recording whose recordable is a
`Comment`, parented to whatever it comments on. `content` → Action Text.

---

## 5. Chat is deliberately *not* a Recording

Campfire-style chat lines are high-volume and ephemeral: they can't be commented
on or trashed individually, only posted and deleted. Wrapping each line in the
full Recording envelope would be over-modeling. So:

- **`Chat`** — the container (belongs to the group/bucket).
- **`Chat::Line`** — a lightweight row: `chat_id`, `creator_id`, `content`,
  `created_at`. Not a recordable, no `parent_id`, no status machinery.

This is an intentional asymmetry, and the one place the model departs from
"everything is a Recording."

---

## 6. People and membership

- **`Person`** — a member (name, email, etc.).
- **`Group`** (the bucket) — the community space.
- **`Membership`** — join between Person and Group (role: owner / member),
  since a person can belong to more than one group and a group has many people.
- Every `Recording.creator_id` → a Person.

---

## 7. Envelope tables implied by the pattern

These come "for free" with the spine and are worth reserving even in a notional
model (flagged because I'm inferring, not observing, their exact shape):

- **`comments`** — recordable table for `Comment` (see §4).
- **`subscriptions`** — who follows a Recording (for notifications).
- **`events`** — per-Recording activity/version log powering the timeline.
- **`boosts`** — emoji reactions on a Recording (Basecamp's "boosts").
- **`action_text_rich_texts`**, **`active_storage_*`** — rich body + attachments.

---

## 8. Assumptions & known gaps

Explicitly notional — these are decisions or unknowns, not settled facts:

1. **Column names are idiomatic guesses**, not Basecamp's real internals.
2. **`bucket` vs `Group` naming** — kept `bucket` internally to match the
   pattern; UI term is *Group*. Could rename fully to `Group` if we don't care
   about pattern fidelity.
3. **Status model** — assumed an enum `active / archived / trashed` on Recording.
4. **Answer↔week keying** (`group_on`) — mechanism assumed, not observed in detail.
5. **Rich text / attachments** — assumed Action Text + Active Storage are in play.
6. **Scheduling** for `Question` — modeled inline on the row; could be extracted
   to a `schedules` table if reused elsewhere.
7. Peripheral tools from the reference project (to-dos, calendar/schedule,
   inbox, cards) are **out of scope** here — this model covers Messages, Docs,
   Question/Answer, and Chat only.

---

## 9. At a glance

```
Person ──< Membership >── Group (bucket)
                            │
        ┌───────────────────┼───────────────────┬─────────────┐
        │                   │                   │             │
   Message::Board         Vault           Questionnaire       Chat
        │                   │                   │             │
     Message   ◀─ Recording ─▶  Document      Question     Chat::Line
        │           (spine)        │             │        (not a recording)
     comments               comments          Answer
   (Recordings)           (Recordings)     (Recording, parent=Question)
```

Everything inside the dashed spine is a `Recording` + recordable pair; `Chat::Line`
is the one lightweight exception.
