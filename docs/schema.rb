# frozen_string_literal: true
#
# NOTIONAL schema for the Writer Group site — a thinking artifact, NOT a real
# migration. Modeled on Basecamp's delegated-type (Record/Recordable) pattern.
# See data-model.md for the narrative. Column names/types are idiomatic guesses;
# anything inferred rather than observed is noted inline.

ActiveRecord::Schema[7.2].define(version: 0) do

  # ── People & membership ────────────────────────────────────────────────────

  create_table "people", force: :cascade do |t|
    t.string   "name",          null: false
    t.string   "email_address", null: false
    t.timestamps
    t.index ["email_address"], unique: true
  end

  # A "bucket" in Basecamp terms — the community space. Exposed as "Group" in UI.
  create_table "groups", force: :cascade do |t|
    t.string   "name",       null: false
    t.text     "description"
    t.timestamps
  end

  create_table "memberships", force: :cascade do |t|
    t.references "person", null: false, foreign_key: true
    t.references "group",  null: false, foreign_key: true
    t.string     "role",   null: false, default: "member"   # owner | member
    t.timestamps
    t.index ["group_id", "person_id"], unique: true
  end

  # ── The spine: Recording (delegated-type parent) ───────────────────────────

  create_table "recordings", force: :cascade do |t|
    # delegated-type pointer to the specific recordable row
    t.string   "recordable_type", null: false
    t.bigint   "recordable_id",   null: false

    t.references "group",   null: false, foreign_key: true   # the bucket
    t.references "creator", null: false,
                 foreign_key: { to_table: :people }

    # self-referential: comments/answers point at their parent recording
    t.bigint   "parent_id"

    t.string   "status",   null: false, default: "active"    # active|archived|trashed
    t.integer  "position"
    t.boolean  "visible_to_members", null: false, default: true
    t.datetime "trashed_at"
    t.timestamps

    t.index ["recordable_type", "recordable_id"], unique: true,
            name: "index_recordings_on_recordable"
    t.index ["group_id", "status"]
    t.index ["parent_id"]
  end
  # add_foreign_key "recordings", "recordings", column: "parent_id"

  # ── Containers (the dock) ──────────────────────────────────────────────────

  create_table "message_boards", force: :cascade do |t|
    t.references "group", null: false, foreign_key: true
    t.string     "name",  null: false      # "Workshop", "Kickoffs", "Heartbeats"
    t.integer    "position"
    t.timestamps
  end

  create_table "vaults", force: :cascade do |t|
    t.references "group", null: false, foreign_key: true
    t.string     "name",  null: false, default: "Docs & Files"
    t.timestamps
  end

  create_table "questionnaires", force: :cascade do |t|
    t.references "group", null: false, foreign_key: true
    t.string     "name",  null: false, default: "Automatic Check-ins"
    t.timestamps
  end

  create_table "chats", force: :cascade do |t|
    t.references "group", null: false, foreign_key: true
    t.string     "name",  null: false, default: "Chat"
    t.timestamps
  end

  # ── Recordables (each is 1:1 with a recording via include Recordable) ───────

  create_table "messages", force: :cascade do |t|
    t.references "message_board", null: false, foreign_key: true
    t.string     "subject",       null: false
    # body lives in Action Text (action_text_rich_texts), not a column here
    t.timestamps
  end

  create_table "documents", force: :cascade do |t|
    t.references "vault", null: false, foreign_key: true
    t.string     "title", null: false
    # body → Action Text
    t.timestamps
  end

  create_table "questions", force: :cascade do |t|
    t.references "questionnaire", null: false, foreign_key: true
    t.string     "title",         null: false          # the recurring prompt
    # recurring schedule (modeled inline; could extract to a schedules table)
    t.string     "frequency",     null: false, default: "every_week"
    t.string     "days_mask"                            # e.g. "1,2,3,4,5" (0=Sun)
    t.time       "time_of_day"
    t.timestamps
  end

  # Question::Answer — one row per member per period
  create_table "answers", force: :cascade do |t|
    t.references "question", null: false, foreign_key: true
    t.date       "group_on", null: false     # the week/day this answer belongs to
    # body → Action Text
    t.timestamps
    t.index ["question_id", "group_on"]
  end

  create_table "comments", force: :cascade do |t|
    # parent linkage lives on the recording (parent_id); this row is just the body
    t.timestamps
    # body → Action Text
  end

  create_table "uploads", force: :cascade do |t|
    t.references "vault", null: false, foreign_key: true
    t.string     "title"
    # file → Active Storage attachment
    t.timestamps
  end

  # ── Chat lines: intentionally NOT recordings (lightweight, high-volume) ─────

  create_table "chat_lines", force: :cascade do |t|
    t.references "chat",    null: false, foreign_key: true
    t.references "creator", null: false, foreign_key: { to_table: :people }
    t.text       "content", null: false     # plain/light markup, no Action Text
    t.datetime   "created_at", null: false
    t.index ["chat_id", "created_at"]
  end

  # ── Envelope tables implied by the pattern (reserved, shapes inferred) ──────

  create_table "subscriptions", force: :cascade do |t|
    t.references "recording", null: false, foreign_key: true
    t.references "person",    null: false, foreign_key: true
    t.timestamps
    t.index ["recording_id", "person_id"], unique: true
  end

  create_table "boosts", force: :cascade do |t|     # emoji reactions
    t.references "recording", null: false, foreign_key: true
    t.references "booster",   null: false, foreign_key: { to_table: :people }
    t.string     "content",   null: false           # the emoji
    t.timestamps
  end

  create_table "events", force: :cascade do |t|     # timeline / activity log
    t.references "recording", null: false, foreign_key: true
    t.references "creator",   null: false, foreign_key: { to_table: :people }
    t.string     "action",    null: false           # created | edited | completed | ...
    t.json       "detail"
    t.timestamps
  end

  # Rich text + attachments (Rails-provided; listed for completeness)
  #   action_text_rich_texts  — polymorphic body storage for recordables
  #   active_storage_blobs / attachments / variant_records — files & images
end
