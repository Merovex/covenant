require "test_helper"

class Webhooks::LemonSqueezyControllerTest < ActionDispatch::IntegrationTest
  SECRET = "test-signing-secret".freeze

  def payload(event, **attributes)
    {
      meta: { event_name: event, custom_data: nil },
      data: { type: "license-keys", id: "77", attributes: {
        store_id: 1, customer_id: 1, order_id: 5, order_item_id: 1, product_id: 1309550,
        user_name: "Grace Hopper", user_email: "grace@example.com", key: "cobol-1959", key_short: "XXXX-cobol-1959",
        activation_limit: 3, instances_count: 0, disabled: false, status: "inactive", expires_at: nil,
        created_at: "2026-08-23T05:03:55.000000Z", updated_at: "2026-08-23T05:03:55.000000Z"
      }.merge(attributes) }
    }.to_json
  end

  def post_webhook(body, signature: OpenSSL::HMAC.hexdigest("SHA256", SECRET, body))
    stubbing(License::LemonSqueezy, :webhook_secret, SECRET) do
      stubbing(License::LemonSqueezy, :product_names, { "1309550" => "Verkilo" }) do
        post lemon_squeezy_webhook_path, params: body, headers: { "CONTENT_TYPE" => "application/json", "X-Signature" => signature }.compact
      end
    end
  end

  test "a signed license_key_created event mirrors the license" do
    assert_difference "Record.licenses.count", 1 do
      post_webhook payload("license_key_created")
    end
    assert_response :ok

    license = License.current.find_by!(external_id: "77")
    assert_equal customers(:grace), license.customer
    assert_equal 3, license.seats
    assert license.active?
  end

  test "a license_key_updated event revises the mirrored license" do
    post_webhook payload("license_key_created")
    post_webhook payload("license_key_updated", status: "disabled", disabled: true)

    assert_response :ok
    assert License.current.find_by!(external_id: "77").revoked?
  end

  test "a bad signature is rejected" do
    assert_no_difference "Record.licenses.count" do
      post_webhook payload("license_key_created"), signature: "nope"
    end
    assert_response :unauthorized
  end

  test "a missing signature is rejected" do
    post_webhook payload("license_key_created"), signature: nil
    assert_response :unauthorized
  end

  def order_payload(event, **attributes)
    {
      meta: { event_name: event },
      data: { type: "orders", id: "555", attributes: {
        store_id: 1, customer_id: 1, identifier: "abc", order_number: 42, user_name: "Grace Hopper", user_email: "grace@example.com",
        currency: "USD", status: "paid", refunded: false, refunded_at: nil, subtotal: 2800, discount_total: 0, tax: 0, total: 2800,
        refunded_amount: 0, total_formatted: "$28.00", first_order_item: { product_name: "Verkilo", variant_name: "Default" },
        urls: { receipt: "https://example.com/r" }, created_at: "2026-08-23T05:03:51.000000Z", test_mode: false
      }.merge(attributes) }
    }.to_json
  end

  test "order_created mirrors the order and order_refunded updates it" do
    assert_difference "Order.count", 1 do
      post_webhook order_payload("order_created")
    end
    assert_response :ok
    order = Order.find_by!(external_id: "555")
    assert_equal customers(:grace), order.customer
    assert order.paid?

    post_webhook order_payload("order_refunded", status: "refunded", refunded: true, refunded_amount: 2800, refunded_at: "2026-08-24T00:00:00.000000Z")
    assert_response :ok
    assert order.reload.refunded?
    assert_equal 2800, order.refunded_amount
  end

  test "other events are acknowledged and ignored" do
    assert_no_difference "Record.licenses.count" do
      post_webhook payload("order_created")
    end
    assert_response :ok
  end

  test "malformed JSON is a bad request" do
    post_webhook "{not json"
    assert_response :bad_request
  end

  test "the endpoint does not exist until a signing secret is configured" do
    stubbing(License::LemonSqueezy, :webhook_secret, nil) do
      post lemon_squeezy_webhook_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
    end
    assert_response :not_found
  end
end
