# A Lemon Squeezy order, mirrored into the desk (ADR 0011). A plain table:
# LS owns the order; we keep the support-relevant slice — who bought what,
# for how much, whether it was refunded — so a customer's purchase history and
# the dashboard's revenue read locally. Written only by License::LemonSqueezy
# (the daily sync and the order_created / order_refunded webhooks).
class Order < ApplicationRecord
  belongs_to :customer

  # LS order statuses: pending / failed / paid / refunded.
  enum :status, %w[ pending failed paid refunded ].index_by(&:itself), default: :paid

  validates :external_id, presence: true, uniqueness: true

  # Real money only: test-mode orders are mirrored (so a test key's license
  # still has its order) but never counted.
  scope :live, -> { where(test_mode: false) }

  def live? = !test_mode?

  # Still refundable in LS: money was taken and not all of it given back.
  def refundable?
    (paid? || refunded?) && refunded_amount < total
  end
  scope :newest_first, -> { order(ordered_at: :desc, id: :desc) }

  # Licenses minted by this order — current versions only, joined on the LS
  # order id both sides carry.
  def licenses
    License.current.where(external_order_id: external_id).includes(:record)
  end

  # "#2776381" — the number on the customer's receipt.
  def display_number
    "##{order_number || external_id}"
  end

  # "Verkilo" or "Verkilo — Pro" when the variant says more than "Default".
  def item_name
    variant = variant_name.presence
    variant && variant != "Default" ? "#{product_name} — #{variant}" : product_name.to_s
  end

  # What the customer is out of pocket after any refund, in cents.
  def net_total
    total - refunded_amount
  end

  # Net takings over a window, by currency: { "USD" => 2800 }. Paid orders only
  # (pending/failed never collected), refunds netted off, test mode excluded.
  def self.revenue(range)
    live.where(status: %w[paid refunded], ordered_at: range)
      .group(:currency).sum(Arel.sql("orders.total - orders.refunded_amount"))
  end
end
