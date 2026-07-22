class CreateReplies < ActiveRecord::Migration[8.2]
  def change
    # Seventh recordable on the spine — every message after a ticket's opener
    # (inbound customer mail or outbound agent mail). Threaded under the
    # ticket's Record via records.parent_id, exactly how comments hang off a
    # post. Rich text body in Action Text; the rest is email metadata.
    #
    # creator_id is NULLABLE: an inbound customer email has no User author.
    # In practice the mailbox stamps it with the seeded system user so the
    # parent Record (creator NOT NULL) still has an author — the column stays
    # nullable so a truly authorless reply remains representable.
    create_table :replies do |t|
      t.integer :record_id, null: false
      t.integer :creator_id
      t.string :event, default: "created", null: false
      t.string :direction, null: false               # inbound|outbound
      t.string :from_address, null: false
      t.string :to_address, null: false
      t.string :subject
      t.string :message_id                            # this email's Message-ID
      t.string :in_reply_to                           # parent Message-ID (Strategy-2 threading)
      t.timestamps

      t.index [ :record_id, :id ]
      t.index :creator_id
      # Idempotent ingest (SNS redelivery echoes the same id). Partial + unique:
      # only the first-ingested version (event "created") is constrained, so
      # successor versions that dup the row and repeat the id don't collide.
      t.index :message_id, unique: true, name: "index_replies_on_ingest_message_id",
        where: "message_id IS NOT NULL AND event = 'created'"
    end

    add_foreign_key :replies, :records
    add_foreign_key :replies, :users, column: :creator_id
  end
end
