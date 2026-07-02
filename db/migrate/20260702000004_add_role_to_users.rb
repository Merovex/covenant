class AddRoleToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :role, :string, null: false, default: "member"
  end
end
