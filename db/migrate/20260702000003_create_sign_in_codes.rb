class CreateSignInCodes < ActiveRecord::Migration[8.2]
  def change
    create_table :sign_in_codes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end
    add_index :sign_in_codes, :code_digest, unique: true
  end
end
