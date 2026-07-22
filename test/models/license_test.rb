require "test_helper"

class LicenseTest < ActiveSupport::TestCase
  setup do
    @customer = customers(:ada)
    @creator = users(:admin)
  end

  def originate_license(key: "COV-1", **attrs)
    license = License.new(customer: @customer, license_key: key, product: "Covenant Pro",
      creator: @creator, **attrs)
    Record.originate(license)
    license
  end

  test "defaults to active and appears in current" do
    license = originate_license
    assert license.active?
    assert_includes License.current, license
  end

  test "never mutable: an edit lands as a new version" do
    license = originate_license
    updated = license.record.revise(event: :updated, status: "suspended")

    assert updated.persisted?
    assert_not_equal license.id, updated.id
    assert_equal 2, license.record.versions.count
    assert license.record.recordable.suspended?
  end

  test "license_key must be unique among current licenses" do
    originate_license(key: "DUP")
    clash = License.new(customer: @customer, license_key: "DUP", product: "X", creator: @creator)

    assert_not clash.valid?
    assert clash.errors[:license_key].any?
  end

  test "a versioned key does not collide with its own record" do
    license = originate_license(key: "SELF")
    # Reissuing the same key on the same record (a later version) is fine.
    updated = license.record.revise(event: :updated, seats: 5)

    assert updated.errors.none?
    assert_equal "SELF", updated.license_key
  end
end
