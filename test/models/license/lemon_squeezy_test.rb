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

  test "sync! pages through the store's keys and stamps the sync time" do
    pages = {
      1 => { "data" => [ resource ], "meta" => { "page" => { "currentPage" => 1, "lastPage" => 2 } } },
      2 => { "data" => [ resource(id: "2", key: "second-key", user_email: "grace@example.com") ], "meta" => { "page" => { "currentPage" => 2, "lastPage" => 2 } } }
    }
    fake_get = ->(path, params = {}) do
      assert_equal "license-keys", path
      pages.fetch(params["page[number]"])
    end

    tally = stubbing(License::LemonSqueezy, :product_names, PRODUCTS) do
      stubbing(License::LemonSqueezy, :get, fake_get) do
        License::LemonSqueezy.sync!(now: Time.utc(2026, 8, 23, 6))
      end
    end

    assert_equal({ created: 2 }, tally)
    assert_equal 2, License.current.external.count
    assert_equal customers(:grace), License.current.find_by!(external_id: "2").customer
  end
end
