require "test_helper"

class SyncLemonSqueezyLicensesJobTest < ActiveJob::TestCase
  test "runs the sync when configured" do
    ran = false
    stubbing(License::LemonSqueezy, :configured?, true) do
      stubbing(License::LemonSqueezy, :sync!, -> { ran = true; {} }) do
        SyncLemonSqueezyLicensesJob.perform_now
      end
    end
    assert ran
  end

  test "is a no-op without an API key" do
    ran = false
    stubbing(License::LemonSqueezy, :configured?, false) do
      stubbing(License::LemonSqueezy, :sync!, -> { ran = true }) do
        SyncLemonSqueezyLicensesJob.perform_now
      end
    end
    assert_not ran
  end
end
