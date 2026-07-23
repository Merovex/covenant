class CreateDownloadStats < ActiveRecord::Migration[8.2]
  def change
    create_table :download_stats do |t|
      t.date :period, null: false      # the day these downloads happened
      t.string :platform, null: false  # mac / windows / linux (/ other)
      t.integer :count, null: false, default: 0
      t.timestamps
    end

    # One row per (day, platform); the sync upserts against this.
    add_index :download_stats, %i[period platform], unique: true
  end
end
