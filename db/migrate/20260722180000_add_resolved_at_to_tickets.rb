class AddResolvedAtToTickets < ActiveRecord::Migration[8.2]
  def change
    add_column :tickets, :resolved_at, :datetime
  end
end
