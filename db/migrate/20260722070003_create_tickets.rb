class CreateTickets < ActiveRecord::Migration[8.2]
  def change
    # Sixth recordable on the spine — a support ticket: the bucket plus the
    # customer's opening email. Rich text opener lives in Action Text
    # (has_rich_text :content), so no body column here. Immutable like a
    # comment: every status change is a new version → free audit trail.
    create_table :tickets do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, default: "created", null: false
      t.integer :customer_id, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "open"
      t.string :from_address                          # opener's From (usually customer.email)
      t.string :message_id                            # opener Message-ID (threading + ingest dedup)
      t.timestamps

      t.index [ :record_id, :id ]
      t.index :record_id
      t.index :creator_id
      t.index :customer_id
      # Dedup inbound openers by Message-ID. Partial + unique: only the opener
      # version (event "created") is constrained, so successor versions — which
      # dup the row and repeat the id — don't collide. NULL ids (in-app tickets)
      # are excluded entirely.
      t.index :message_id, unique: true, name: "index_tickets_on_opener_message_id",
        where: "message_id IS NOT NULL AND event = 'created'"
    end

    add_foreign_key :tickets, :records
    add_foreign_key :tickets, :users, column: :creator_id
    add_foreign_key :tickets, :customers
  end
end
