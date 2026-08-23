require "test_helper"

# The staff-facing side of the Lemon Squeezy mirror: the sync button, the
# activations panel, and the edit lock on mirrored licenses.
class LicensesLemonSqueezyTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @license = License.new(customer: customers(:ada), license_key: "ls-key", product: "Verkilo",
      creator: users(:admin), external_id: "1555330", external_order_id: "9", instances_count: 2)
    Record.originate(@license)
  end

  test "sync button pulls from Lemon Squeezy and reports the tally" do
    stubbing(License::LemonSqueezy, :sync!, { created: 1, unchanged: 2 }) do
      post sync_licenses_path
    end

    assert_redirected_to licenses_path
    assert_equal "Synced from Lemon Squeezy: 1 created, 2 unchanged.", flash[:notice]
  end

  test "a failed sync is reported, not raised" do
    stubbing(License::LemonSqueezy, :sync!, ->(*) { raise "HTTP 500" }) do
      post sync_licenses_path
    end

    assert_redirected_to licenses_path
    assert_match "HTTP 500", flash[:alert]
  end

  test "the license page shows provenance and a lazy activations frame" do
    get license_path(@license.record)

    assert_response :ok
    assert_select "p", /Mirrored from Lemon Squeezy/
    assert_select "dd", /2 \/ ∞/
    assert_select "turbo-frame[src=?]", license_activations_path(@license.record)
    assert_select "a", text: "Edit", count: 0
  end

  test "the activations panel lists machines from Lemon Squeezy" do
    instances = [ { "identifier" => "abc-123", "name" => "Verkilo (019fad5e)", "created_at" => "2026-08-23T05:04:28.000000Z" } ]
    stubbing(License::LemonSqueezy, :instances, instances) do
      get license_activations_path(@license.record)
    end

    assert_response :ok
    assert_select "td", "Verkilo (019fad5e)"
    assert_select "code", "abc-123"
  end

  test "the activations panel degrades to a note when Lemon Squeezy is unreachable" do
    stubbing(License::LemonSqueezy, :instances, ->(*) { raise "connection refused" }) do
      get license_activations_path(@license.record)
    end

    assert_response :ok
    assert_select "p", /connection refused/
  end

  test "a mirrored license can't be edited here" do
    get edit_license_path(@license.record)
    assert_redirected_to license_path(@license.record)

    patch license_path(@license.record), params: { license: { status: "suspended" } }
    assert_redirected_to license_path(@license.record)
    assert @license.record.reload.recordable.active?
  end

  test "a hand-entered license still edits" do
    manual = License.new(customer: customers(:ada), license_key: "manual", product: "Verkilo", creator: users(:admin))
    Record.originate(manual)

    get edit_license_path(manual.record)
    assert_response :ok
  end
end
