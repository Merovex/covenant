class User < ApplicationRecord
  include Registration

  AVATAR_CONTENT_TYPES = %w[ image/jpeg image/png image/avif image/webp ]
  AVATAR_MAX_SIZE = 5.megabytes

  has_many :sessions, dependent: :destroy
  has_many :sign_in_codes, dependent: :destroy
  # Exists so "your own boost" authorization can be a scope (BoostsController).
  has_many :boosts, foreign_key: :creator_id, inverse_of: :creator, dependent: :delete_all

  # The uploaded picture behind the avatar; absent means the monogram
  # (see ApplicationHelper#avatar_content).
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_fill: [ 160, 160 ]
  end

  validate :acceptable_avatar

  # :member is the baseline; :domain_admin is granted to the first user ever (via
  # the Setup flow) and administers the whole install. :system is the app
  # itself — the author of record for content the support desk ingests from
  # email (inbound tickets/replies have no human author). It never signs in.
  enum :role, { member: "member", domain_admin: "domain_admin", system: "system" }, default: :member

  # The seeded system account. Stamped as the creator on inbound-ingested
  # tickets and replies so the parent Record (creator NOT NULL) always has an
  # author. Idempotent: safe to call before seeds have run (e.g. in tests).
  def self.system
    find_or_create_by!(role: :system) do |user|
      user.email_address = "support@#{ApplicationMailer.inbound_domain}"
      user.name = "Covenant Support"
    end
  end

  normalizes :email_address, with: -> { it.strip.downcase }

  # Uniqueness is enforced by the unique index on email_address; nothing surfaces
  # a duplicate to a user (setup can't dup, signup reuses), so no validation here.
  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # What we call the user everywhere: their name, or their email until
  # they've set one.
  def display_name
    name.presence || email_address
  end

  # Generate a fresh single-use code and email its magic link. `purpose`
  # (:sign_in / :sign_up) tunes the email copy.
  def send_magic_link(purpose: :sign_in)
    code = sign_in_codes.create!
    SessionMailer.magic_link(self, code.plaintext, purpose:).deliver_later
  end

  private
    def acceptable_avatar
      return unless avatar.attached?

      unless avatar.blob.content_type.in?(AVATAR_CONTENT_TYPES)
        errors.add(:avatar, "must be a JPG, PNG, AVIF, or WebP image")
      end
      if avatar.blob.byte_size > AVATAR_MAX_SIZE
        errors.add(:avatar, "must be smaller than #{AVATAR_MAX_SIZE / 1.megabyte} MB")
      end
    end
end
