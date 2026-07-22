# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# The message board's default categories (Basecamp's set). Idempotent by
# name; icons only apply on first creation, so renamed icons stick.
[
  [ "📢", "Announcement" ],
  [ "✋", "FYI" ],
  [ "💓", "Heartbeat" ],
  [ "💡", "Pitch" ],
  [ "🤔", "Question" ]
].each do |icon, name|
  Category.find_or_create_by!(name: name) { |category| category.icon = icon }
end

# The support desk's system account — author of record for tickets/replies the
# app ingests from email (inbound mail has no human author). Idempotent.
User.system
