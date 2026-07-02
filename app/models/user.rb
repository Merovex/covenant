class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :sign_in_codes, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }
end
