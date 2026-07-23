# Refreshes the local download tally from the Cloudflare downloads Worker.
# Scheduled hourly in config/recurring.yml, and enqueued by the "Refresh" button
# on the downloads dashboard.
class SyncDownloadStatsJob < ApplicationJob
  def perform
    DownloadStat.sync!
  end
end
