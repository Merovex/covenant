require "net/http"

# Refreshes the local download tally from the Cloudflare downloads Worker.
# Scheduled hourly in config/recurring.yml, and enqueued by the "Refresh" button
# on the downloads dashboard.
class SyncDownloadStatsJob < ApplicationJob
  # The Worker queries Analytics Engine, which is occasionally slow to answer;
  # a one-off timeout isn't worth an alert. Retries still re-raise once
  # exhausted, so a real outage surfaces in Honeybadger.
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 3

  def perform
    DownloadStat.sync!
  end
end
