require "test_helper"

# The customer page's layout: glance cards, Tickets-first segmented panels,
# and the row actions that write back to Lemon Squeezy.
class CustomersPageTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @customer = customers(:ada)
    @license = License.new(customer: @customer, license_key: "ls-key-1", product: "Verkilo", creator: users(:admin),
      external_id: "1555330", external_order_id: "9284193", instances_count: 2)
    Record.originate(@license)
    @order = Order.create!(external_id: "9284193", customer: @customer, order_number: 2776381, status: "paid",
      total: 2800, currency: "USD", product_name: "Verkilo", variant_name: "Default", ordered_at: Time.current)
  end

  test "glance row, tickets-first tabs with counts, and last activity" do
    get customer_path(@customer)

    assert_response :ok
    assert_select ".dashboard__stats .dashboard__stat", 4
    assert_select ".dashboard__stat-number", text: "Active"
    assert_select ".dashboard__stat-number", text: "2 / ∞"
    assert_select ".dashboard__stat-number", text: "$28.00"
    assert_select ".dashboard__stat-number", text: "None"
    assert_select "a.button", text: "Email customer"

    assert_select "[role=tablist] [role=tab]" do |tabs|
      assert_equal [ "Tickets 0", "Licenses 1", "Orders 1" ], tabs.map { |t| t.text.squish }
      assert_equal "true", tabs.first["aria-selected"]
    end
    assert_select ".customer__tabs-head", /Last activity/
    assert_select "#customer-panel-tickets", /No tickets on record/
    assert_select "#customer-panel-tickets a.button", "Open one"
  end

  test "license rows offer Copy key and Revoke; order rows Receipt and Refund" do
    get customer_path(@customer)

    assert_select "#customer-panel-licenses" do
      assert_select "code", "ls-key-1"
      assert_select "[data-clipboard-text-value=?]", "ls-key-1"
      assert_select "form[action=?]", revoke_license_path(@license.record)
      assert_select ".list__meta", /2 of ∞ activations · issued with order #2776381/
    end
    assert_select "#customer-panel-orders" do
      assert_select "a[href=?]", receipt_order_path(@order), text: "Receipt"
      assert_select "form[action=?]", refund_order_path(@order)
    end
  end

  test "a hand-entered license has no Revoke and a refunded order no Refund" do
    manual = License.new(customer: @customer, license_key: "manual", product: "Verkilo", creator: users(:admin))
    Record.originate(manual)
    @order.update!(status: "refunded", refunded: true, refunded_amount: 2800)

    get customer_path(@customer)
    assert_select "form[action=?]", revoke_license_path(manual.record), count: 0
    assert_select "form[action=?]", refund_order_path(@order), count: 0
    assert_select ".dashboard__stat-number", text: "$0.00"
  end

  test "revoke disables the key in Lemon Squeezy and comes back" do
    called = nil
    stubbing(License::LemonSqueezy, :disable!, ->(id) { called = id; :updated }) do
      post revoke_license_path(@license.record), headers: { "HTTP_REFERER" => customer_url(@customer) }
    end
    assert_equal "1555330", called
    assert_redirected_to customer_url(@customer)
    assert_match "revoked", flash[:notice]
  end

  test "revoke refuses a hand-entered license" do
    manual = License.new(customer: @customer, license_key: "manual", product: "Verkilo", creator: users(:admin))
    Record.originate(manual)
    post revoke_license_path(manual.record)
    assert_response :not_found
  end

  test "refund goes through Lemon Squeezy and reports failure" do
    called = nil
    stubbing(License::LemonSqueezy, :refund!, ->(id, **) { called = id; :updated }) do
      post refund_order_path(@order), headers: { "HTTP_REFERER" => customer_url(@customer) }
    end
    assert_equal "9284193", called
    assert_redirected_to customer_url(@customer)
    assert_match "refunded", flash[:notice]

    stubbing(License::LemonSqueezy, :refund!, ->(*) { raise "HTTP 422 already refunded" }) do
      post refund_order_path(@order)
    end
    assert_redirected_to order_path(@order)
    assert_match "already refunded", flash[:alert]
  end
end
