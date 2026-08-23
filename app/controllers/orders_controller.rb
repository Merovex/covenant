# Orders mirrored from Lemon Squeezy — read-only here (LS owns them; the sync
# and webhooks write them). Admin only. The receipt link goes back to LS for a
# freshly signed URL, since the ones LS hands out expire within hours.
class OrdersController < ApplicationController
  before_action -> { authorize! Order, to: :manage }
  before_action :set_order, only: %i[show receipt]

  def index
    scope = Order.includes(:customer).newest_first
    @refunded = params[:refunded].present?
    scope = scope.where(refunded: true) if @refunded
    @orders = scope
    @counts = { all: Order.count, refunded: Order.where(refunded: true).count }
  end

  def show
    @licenses = @order.licenses
  end

  # Bounce to the customer's receipt on Lemon Squeezy.
  def receipt
    url = License::LemonSqueezy.receipt_url(@order.external_id)
    raise "Lemon Squeezy returned no receipt link" if url.blank?

    redirect_to url, allow_other_host: true
  rescue => e
    redirect_to order_path(@order), alert: "Couldn't fetch the receipt: #{e.message}"
  end

  private
    def set_order
      @order = Order.find(params[:id])
    end
end
