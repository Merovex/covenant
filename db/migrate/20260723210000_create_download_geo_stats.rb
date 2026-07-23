class CreateDownloadGeoStats < ActiveRecord::Migration[8.2]
  def change
    create_table :download_geo_stats do |t|
      t.string :country, null: false               # ISO 3166-1 alpha-2, e.g. "US"
      t.string :region, null: false, default: ""   # state / province name
      t.integer :count, null: false, default: 0
      t.timestamps
    end

    add_index :download_geo_stats, %i[country region], unique: true
  end
end
