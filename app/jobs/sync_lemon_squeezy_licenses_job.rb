require "net/http"

# Mirrors Lemon Squeezy license keys into License. Scheduled hourly in
# config/recurring.yml and enqueued by the "Sync" button on the licenses index;
# the webhook keeps things fresh in between, this is the backstop that catches
# anything it missed.
class SyncLemonSqueezyLicensesJob < ApplicationJob
  # One slow answer isn't worth an alert; exhausted retries re-raise, so a real
  # outage still surfaces in Honeybadger.
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 3

  def perform
    return unless License::LemonSqueezy.configured?

    License::LemonSqueezy.sync!
  end
end
