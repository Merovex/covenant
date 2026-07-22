class CreateCustomers < ActiveRecord::Migration[8.2]
  def change
    # The support desk's "collector": an external party who owns licenses and
    # files tickets. A plain lookup table (like categories), NOT a User — no
    # sign-in, just an email we recognise inbound mail by.
    create_table :customers do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :company
      t.text :notes
      t.timestamps

      t.index :email, unique: true
    end
  end
end
