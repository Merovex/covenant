class CreateLicenses < ActiveRecord::Migration[8.2]
  def change
    # Fifth recordable on the spine — a customer's product license. Versioned
    # like every recordable (renewals/status changes are history), but no rich
    # text and no publish regime: it just includes Recordable. The envelope
    # (creator, trash) lives on the license's Record.
    create_table :licenses do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, default: "created", null: false
      t.integer :customer_id, null: false
      t.string :license_key, null: false
      t.string :product, null: false
      t.integer :seats, null: false, default: 1
      t.datetime :issued_at
      t.datetime :expires_at
      t.string :status, null: false, default: "active"
      t.timestamps

      t.index [ :record_id, :id ]
      t.index :creator_id
      t.index :customer_id
    end

    add_foreign_key :licenses, :records
    add_foreign_key :licenses, :users, column: :creator_id
    add_foreign_key :licenses, :customers
  end
end
