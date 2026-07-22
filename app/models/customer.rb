# The support desk's external party — owns licenses and files tickets. A
# plain lookup table (no spine, no versioning), recognised on inbound mail by
# its normalised email. NOT a User: customers never sign in.
class Customer < ApplicationRecord
  include Notable # a staff-only rich-text note

  # customer_id is NOT NULL on both (and versioned — many rows per record share
  # it), so a customer with any history can't be nullified away: block the
  # delete with an error instead. Rename/merge, don't destroy.
  has_many :licenses, dependent: :restrict_with_error
  has_many :tickets, dependent: :restrict_with_error

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :name, :email, presence: true
  validates :email, uniqueness: true

  def display_name
    name.presence || email
  end
end
