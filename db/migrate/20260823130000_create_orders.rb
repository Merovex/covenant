class CreateOrders < ActiveRecord::Migration[8.2]
  def change
    # Orders mirrored from Lemon Squeezy (ADR 0011). A plain table, not a
    # recordable: LS owns the order and its one status flip (paid → refunded)
    # is carried by refunded/refunded_at, so no version history is needed.
    # external_id is the LS order id — a real unique index here (no versions to
    # repeat it). Money is integer cents in `currency`; *_formatted strings are
    # kept as LS renders them so the desk shows what the receipt shows.
    create_table :orders do |t|
      t.string :external_id, null: false
      t.integer :customer_id, null: false
      t.integer :order_number
      t.string :identifier
      t.string :status, null: false, default: "paid"
      t.boolean :refunded, null: false, default: false
      t.datetime :refunded_at
      t.string :currency, null: false, default: "USD"
      t.integer :subtotal, null: false, default: 0
      t.integer :discount_total, null: false, default: 0
      t.integer :tax, null: false, default: 0
      t.integer :total, null: false, default: 0
      t.integer :refunded_amount, null: false, default: 0
      t.string :total_formatted
      t.string :product_name
      t.string :variant_name
      t.boolean :test_mode, null: false, default: false
      t.datetime :ordered_at
      t.timestamps

      t.index :external_id, unique: true
      t.index :customer_id
      t.index :ordered_at
    end

    add_foreign_key :orders, :customers
  end
end
