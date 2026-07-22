# A customer's product license — a recordable (versioned) row with no rich
# text and no publish regime. Immutable like a comment: every renewal, seat
# change or status flip is a new version, so the history is the audit trail.
class License < ApplicationRecord
  include Recordable

  belongs_to :customer

  enum :status, %w[ active suspended expired revoked ].index_by(&:itself), default: :active

  validates :license_key, :product, presence: true
  validate :license_key_unique_among_current

  # Current versions of live licenses — mirrors Publishable#current.
  scope :current, -> { where(id: Record.active.where(recordable_type: "License").select(:recordable_id)) }

  def mutable? = false

  private
    # Uniqueness is per live license, not per version row (versions repeat the
    # key), so it can't be a bare DB index — check against the current set,
    # excluding this license's own record.
    def license_key_unique_among_current
      return if license_key.blank?

      dupes = License.current.where(license_key: license_key).where.not(record_id: record_id)
      errors.add(:license_key, "is already in use") if dupes.exists?
    end
end
