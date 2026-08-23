class AddLemonSqueezyToLicenses < ActiveRecord::Migration[8.2]
  def change
    # Licenses mirrored from Lemon Squeezy. external_id is the LS license-key
    # id — the idempotency handle for the sync (unique among *current*
    # versions, validated in the model; version rows repeat it, so no unique
    # index). activation_limit is nil for unlimited keys; instances_count is
    # how many machines the key is activated on, as of the last sync.
    change_table :licenses do |t|
      t.string :external_id
      t.string :external_order_id
      t.integer :activation_limit
      t.integer :instances_count, null: false, default: 0
      t.index :external_id
    end
  end
end
