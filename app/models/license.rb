# A customer's product license — a recordable (versioned) row with no rich
# text and no publish regime. Immutable like a comment: every renewal, seat
# change or status flip is a new version, so the history is the audit trail.
#
# Two provenances share the table: hand-entered licenses (the form) and
# licenses mirrored from Lemon Squeezy (external_id set — see
# License::LemonSqueezy). Mirrored ones are edited in LS, not here; the sync
# writes "synced" versions.
class License < ApplicationRecord
  include Recordable

  belongs_to :customer

  enum :status, %w[ active suspended expired revoked ].index_by(&:itself), default: :active

  validates :license_key, :product, presence: true
  validate :license_key_unique_among_current
  validate :external_id_unique_among_current

  # Current versions of live licenses — mirrors Publishable#current.
  scope :current, -> { where(id: Record.active.where(recordable_type: "License").select(:recordable_id)) }
  scope :external, -> { where.not(external_id: nil) }

  def mutable? = false

  # Mirrored from Lemon Squeezy (vs. typed in by staff).
  def external? = external_id.present?

  # The mirrored LS order that minted this key, when we have it.
  def order
    Order.find_by(external_id: external_order_id) if external_order_id.present?
  end

  # "XXXX-" + the last 12 characters — how Lemon Squeezy shows a key in its
  # dashboard and receipts, so staff and customers can match it by eye.
  def key_short
    "XXXX-#{license_key.to_s.last(12)}"
  end

  # Activations as "used / limit" — limit is nil for unlimited keys.
  def activations
    "#{instances_count} / #{activation_limit || "∞"}"
  end

  private
    # Uniqueness is per live license, not per version row (versions repeat the
    # key), so it can't be a bare DB index — check against the current set,
    # excluding this license's own record.
    def license_key_unique_among_current
      return if license_key.blank?

      dupes = License.current.where(license_key: license_key).where.not(record_id: record_id)
      errors.add(:license_key, "is already in use") if dupes.exists?
    end

    # Same trap for the Lemon Squeezy id: one live license per LS key.
    def external_id_unique_among_current
      return if external_id.blank?

      dupes = License.current.where(external_id: external_id).where.not(record_id: record_id)
      errors.add(:external_id, "is already mirrored") if dupes.exists?
    end
end
