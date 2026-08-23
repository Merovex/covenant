require "test_helper"

class License::LemonSqueezyTest < ActiveSupport::TestCase
  PRODUCTS = { "1309550" => "Verkilo" }.freeze

  # An LS license-key resource as the API and webhooks deliver it.
  def resource(id: "1555330", **overrides)
    attributes = {
      "store_id" => 277638, "customer_id" => 9686817, "order_id" => 9284193, "order_item_id" => 1,
      "product_id" => 1309550, "user_name" => "Benjamin Wilson", "user_email" => "Ben@Example.com",
      "key" => "80e15db5-c796-436b-850c-8f9c98a48abe", "key_short" => "XXXX-8f9c98a48abe",
      "activation_limit" => nil, "instances_count" => 2, "disabled" => false, "status" => "active",
      "expires_at" => nil, "created_at" => "2026-08-23T05:03:55.000000Z", "updated_at" => "2026-08-23T05:05:25.000000Z"
    }.merge(overrides.transform_keys(&:to_s))
    { "type" => "license-keys", "id" => id, "attributes" => attributes }
  end

  test "a new key originates a license and its customer" do
    assert_difference [ "Customer.count", "Record.licenses.count" ], 1 do
      assert_equal :created, License::LemonSqueezy.upsert(resource, products: PRODUCTS)
    end

    license = License.current.find_by!(external_id: "1555330")
    assert_equal "Verkilo", license.product
    assert_equal "80e15db5-c796-436b-850c-8f9c98a48abe", license.license_key
    assert_equal "9284193", license.external_order_id
    assert_nil license.activation_limit
    assert_equal 2, license.instances_count
    assert_equal "active", license.status
    assert_equal Time.utc(2026, 8, 23, 5, 3, 55), license.issued_at
    assert_nil license.expires_at
    assert_equal users(:system), license.creator
    assert_equal "ben@example.com", license.customer.email
    assert_equal "Benjamin Wilson", license.customer.name
    assert_equal "XXXX-8f9c98a48abe", license.key_short
    assert_equal "2 / ∞", license.activations
  end

  test "matches an existing customer by email without renaming them" do
    License::LemonSqueezy.upsert(resource(user_email: "ADA@example.com", user_name: "A. Lovelace"), products: PRODUCTS)

    license = License.current.find_by!(external_id: "1555330")
    assert_equal customers(:ada), license.customer
    assert_equal "Ada Lovelace", customers(:ada).reload.name
  end

  test "an unchanged key is a no-op" do
    License::LemonSqueezy.upsert(resource, products: PRODUCTS)

    assert_no_difference "License.count" do
      assert_equal :unchanged, License::LemonSqueezy.upsert(resource, products: PRODUCTS)
    end
  end

  test "a changed key revises the license with a synced version" do
    License::LemonSqueezy.upsert(resource, products: PRODUCTS)
    record = License.current.find_by!(external_id: "1555330").record

    assert_difference "License.count", 1 do
      assert_equal :updated, License::LemonSqueezy.upsert(resource(status: "disabled", disabled: true, instances_count: 3), products: PRODUCTS)
    end

    current = record.reload.recordable
    assert current.revoked?
    assert_equal 3, current.instances_count
    assert current.event_synced?
    assert_equal 2, record.versions.count
  end

  test "status mapping: inactive is still a live license, expired expires, disabled revokes" do
    assert_equal "active",  License::LemonSqueezy.attributes_for(resource(status: "inactive"), PRODUCTS)[:status]
    assert_equal "expired", License::LemonSqueezy.attributes_for(resource(status: "expired"), PRODUCTS)[:status]
    assert_equal "revoked", License::LemonSqueezy.attributes_for(resource(status: "disabled"), PRODUCTS)[:status]
    assert_equal "revoked", License::LemonSqueezy.attributes_for(resource(status: "active", disabled: true), PRODUCTS)[:status]
  end

  test "an unknown product falls back to its id and a limit maps to seats" do
    attrs = License::LemonSqueezy.attributes_for(resource(product_id: 42, activation_limit: 5, expires_at: "2027-01-01T00:00:00.000000Z"), PRODUCTS)

    assert_equal "Product 42", attrs[:product]
    assert_equal 5, attrs[:seats]
    assert_equal 5, attrs[:activation_limit]
    assert_equal Time.utc(2027, 1, 1), attrs[:expires_at]
  end

  test "a trashed mirror is left alone rather than re-originated" do
    License::LemonSqueezy.upsert(resource, products: PRODUCTS)
    License.current.find_by!(external_id: "1555330").record.trash

    assert_no_difference "Record.licenses.count" do
      assert_equal :skipped, License::LemonSqueezy.upsert(resource(instances_count: 9), products: PRODUCTS)
    end
  end

  test "a key without an email is refused" do
    assert_raises ArgumentError do
      License::LemonSqueezy.upsert(resource(user_email: ""), products: PRODUCTS)
    end
  end

  test "sync! pages through the store's orders and keys and stamps the sync time" do
    pages = {
      "license-keys" => {
        1 => { "data" => [ resource ], "meta" => { "page" => { "currentPage" => 1, "lastPage" => 2 } } },
        2 => { "data" => [ resource(id: "2", key: "second-key", user_email: "grace@example.com") ], "meta" => { "page" => { "currentPage" => 2, "lastPage" => 2 } } }
      },
      "orders" => {
        1 => { "data" => [ order_resource ], "meta" => { "page" => { "currentPage" => 1, "lastPage" => 1 } } }
      }
    }
    fake_get = ->(path, params = {}) { pages.fetch(path).fetch(params["page[number]"]) }

    tally = stubbing(License::LemonSqueezy, :product_names, PRODUCTS) do
      stubbing(License::LemonSqueezy, :get, fake_get) do
        License::LemonSqueezy.sync!(now: Time.utc(2026, 8, 23, 6))
      end
    end

    assert_equal({ orders: { created: 1 }, licenses: { created: 2 } }, tally)
    assert_equal "orders 1 created; licenses 2 created", License::LemonSqueezy.describe(tally)
    assert_equal 2, License.current.external.count
    assert_equal customers(:grace), License.current.find_by!(external_id: "2").customer
    assert_equal Order.find_by!(external_id: "9284193"), License.current.find_by!(external_id: "1555330").order
  end

  # -- orders --------------------------------------------------------------

  def order_resource(id: "9284193", **overrides)
    attributes = {
      "store_id" => 277638, "customer_id" => 9686817, "identifier" => "89fc455e-72df-4522-9713-113dcbe197ae",
      "order_number" => 2776381, "user_name" => "Benjamin Wilson", "user_email" => "ben@example.com",
      "currency" => "USD", "status" => "paid", "refunded" => false, "refunded_at" => nil,
      "subtotal" => 12800, "discount_total" => 10000, "tax" => 189, "total" => 2800, "refunded_amount" => 0,
      "total_formatted" => "$28.00",
      "first_order_item" => { "product_id" => 1309550, "variant_id" => 1, "product_name" => "Verkilo", "variant_name" => "Default", "price" => 12800 },
      "urls" => { "receipt" => "https://app.lemonsqueezy.com/my-orders/89fc455e?signature=abc" },
      "created_at" => "2026-08-23T05:03:51.000000Z", "updated_at" => "2026-08-23T05:04:56.000000Z", "test_mode" => false
    }.merge(overrides.transform_keys(&:to_s))
    { "type" => "orders", "id" => id, "attributes" => attributes }
  end

  test "a new order is mirrored onto its customer" do
    assert_difference [ "Order.count", "Customer.count" ], 1 do
      assert_equal :created, License::LemonSqueezy.upsert_order(order_resource)
    end

    order = Order.find_by!(external_id: "9284193")
    assert_equal 2776381, order.order_number
    assert_equal "#2776381", order.display_number
    assert_equal "Verkilo", order.item_name
    assert_equal 2800, order.total
    assert_equal 10000, order.discount_total
    assert_equal "USD", order.currency
    assert order.paid?
    assert_not order.refunded?
    assert_equal Time.utc(2026, 8, 23, 5, 3, 51), order.ordered_at
    assert_equal "ben@example.com", order.customer.email
  end

  test "an unchanged order is a no-op and a refund updates it in place" do
    License::LemonSqueezy.upsert_order(order_resource)
    assert_equal :unchanged, License::LemonSqueezy.upsert_order(order_resource)

    assert_no_difference "Order.count" do
      assert_equal :updated, License::LemonSqueezy.upsert_order(order_resource(
        status: "refunded", refunded: true, refunded_at: "2026-08-24T10:00:00.000000Z", refunded_amount: 2800))
    end
    order = Order.find_by!(external_id: "9284193")
    assert order.refunded?
    assert_equal 2800, order.refunded_amount
    assert_equal 0, order.net_total
  end

  test "a variant other than Default shows in the item name" do
    License::LemonSqueezy.upsert_order(order_resource(first_order_item: { "product_name" => "Verkilo", "variant_name" => "Pro" }))
    assert_equal "Verkilo — Pro", Order.find_by!(external_id: "9284193").item_name
  end

  test "revenue nets refunds, skips test mode and unpaid orders, and groups by currency" do
    License::LemonSqueezy.upsert_order(order_resource)
    License::LemonSqueezy.upsert_order(order_resource(id: "2", order_number: 2, status: "refunded", refunded: true, refunded_amount: 1000, total: 1000))
    License::LemonSqueezy.upsert_order(order_resource(id: "3", order_number: 3, test_mode: true, total: 99900))
    License::LemonSqueezy.upsert_order(order_resource(id: "4", order_number: 4, status: "pending", total: 5000))
    License::LemonSqueezy.upsert_order(order_resource(id: "5", order_number: 5, currency: "EUR", total: 1500))

    assert_equal({ "USD" => 2800, "EUR" => 1500 }, Order.revenue(Time.utc(2026, 8, 1)..Time.utc(2026, 9, 1)))
    assert_equal({}, Order.revenue(Time.utc(2025, 1, 1)..Time.utc(2025, 2, 1)))
  end

  # -- write-backs ---------------------------------------------------------

  test "disable! PATCHes the key and mirrors LS's answer" do
    License::LemonSqueezy.upsert(resource, products: PRODUCTS)
    seen = nil
    fake = ->(verb, path, params: {}, body: nil) do
      seen = [ verb, path, body ]
      { "data" => resource(status: "disabled", disabled: true) }
    end

    result = stubbing(License::LemonSqueezy, :product_names, PRODUCTS) do
      stubbing(License::LemonSqueezy, :request, fake) { License::LemonSqueezy.disable!("1555330") }
    end

    assert_equal :updated, result
    assert_equal [ Net::HTTP::Patch, "license-keys/1555330", { data: { type: "license-keys", id: "1555330", attributes: { disabled: true } } } ], seen
    assert License.current.find_by!(external_id: "1555330").revoked?
  end

  test "refund! POSTs the refund and mirrors LS's answer" do
    License::LemonSqueezy.upsert_order(order_resource)
    seen = nil
    fake = ->(verb, path, params: {}, body: nil) do
      seen = [ verb, path, body ]
      { "data" => order_resource(status: "refunded", refunded: true, refunded_amount: 2800) }
    end

    result = stubbing(License::LemonSqueezy, :request, fake) { License::LemonSqueezy.refund!("9284193") }

    assert_equal :updated, result
    assert_equal [ Net::HTTP::Post, "orders/9284193/refund", { data: { type: "orders", id: "9284193", attributes: {} } } ], seen
    assert Order.find_by!(external_id: "9284193").refunded?
  end
end
