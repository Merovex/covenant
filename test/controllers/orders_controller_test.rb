require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @order = Order.create!(external_id: "9284193", customer: customers(:ada), order_number: 2776381, identifier: "89fc",
      status: "paid", total: 2800, subtotal: 12800, discount_total: 10000, tax: 189, currency: "USD",
      product_name: "Verkilo", variant_name: "Default", ordered_at: Time.utc(2026, 8, 23, 5, 3, 51))
    @refund = Order.create!(external_id: "2", customer: customers(:grace), order_number: 2, status: "refunded",
      refunded: true, refunded_at: Time.utc(2026, 8, 24), refunded_amount: 1000, total: 1000,
      product_name: "Verkilo", ordered_at: Time.utc(2026, 8, 22))
  end

  test "index lists orders newest first and filters refunds" do
    get orders_path
    assert_response :ok
    assert_select "li.list__item", 2
    assert_select "a", /All \(2\)/
    assert_select "a", /Refunded \(1\)/
    assert_select "li.list__item:first-child .list__title", /#2776381/

    get orders_path(refunded: 1)
    assert_select "li.list__item", 1
    assert_select ".status-pill--refunded", "Refunded"
  end

  test "show renders the money breakdown and the order's licenses" do
    license = License.new(customer: customers(:ada), license_key: "k", product: "Verkilo", creator: users(:admin),
      external_id: "1", external_order_id: "9284193")
    Record.originate(license)

    get order_path(@order)
    assert_response :ok
    assert_select "h1", "Order #2776381"
    assert_select "dd", /\$28\.00/
    assert_select "dd", /discount −\$100\.00/
    assert_select "a[href=?]", license_path(license.record)
    assert_select "a[href=?]", receipt_order_path(@order)
  end

  test "receipt bounces to a freshly signed Lemon Squeezy link" do
    stubbing(License::LemonSqueezy, :receipt_url, "https://app.lemonsqueezy.com/my-orders/89fc?signature=fresh") do
      get receipt_order_path(@order)
    end
    assert_redirected_to "https://app.lemonsqueezy.com/my-orders/89fc?signature=fresh"
  end

  test "a failed receipt fetch lands back on the order with an alert" do
    stubbing(License::LemonSqueezy, :receipt_url, ->(*) { raise "HTTP 500" }) do
      get receipt_order_path(@order)
    end
    assert_redirected_to order_path(@order)
    assert_match "HTTP 500", flash[:alert]
  end

  test "the customer page lists their orders" do
    get customer_path(customers(:ada))
    assert_response :ok
    assert_select "a[href=?]", order_path(@order)
  end

  test "the dashboard shows net revenue" do
    get root_path
    assert_response :ok
    assert_select "h2", "Revenue"
    assert_select ".dashboard__stat-number", /\$28\.00/
  end

  test "non-admins get a 404" do
    sign_in_as users(:alice)
    get orders_path
    assert_response :not_found
  end
end
