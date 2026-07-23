require "net/http"

# A daily, per-platform download tally for the desktop app, mirrored from the
# Cloudflare downloads Worker (downloads.verkilo.com/stats.json). We snapshot it
# into our own table so the history survives Analytics Engine's ~90-day
# retention and the dashboard reads locally instead of hitting Cloudflare on
# every page load. SyncDownloadStatsJob refreshes it hourly.
class DownloadStat < ApplicationRecord
  validates :period, presence: true
  validates :platform, presence: true, uniqueness: { scope: :period }

  class << self
    # Downloads within a date range, grouped by platform: { "mac" => 88, … }.
    def by_platform(range)
      where(period: range).group(:platform).sum(:count)
    end

    # Total downloads within a date range.
    def total(range)
      where(period: range).sum(:count)
    end

    # Pull the Worker's daily series and upsert it. Idempotent — re-running
    # overwrites each (period, platform) with the latest count. Returns the
    # number of rows written.
    def sync!(now: Time.current)
      series = Worker.fetch.fetch("series", [])
      rows = series.filter_map do |row|
        period, platform = row["period"], row["platform"]
        next if period.blank? || platform.blank?
        { period:, platform:, count: row["downloads"].to_i, created_at: now, updated_at: now }
      end
      return 0 if rows.empty?

      upsert_all(rows, unique_by: %i[period platform])
      rows.size
    end
  end

  # Thin HTTP client for the downloads Worker's /stats.json endpoint.
  module Worker
    module_function

    DEFAULT_URL = "https://downloads.verkilo.com/stats.json".freeze

    def url
      ENV.fetch("VERKILO_DOWNLOADS_STATS_URL", DEFAULT_URL)
    end

    def token
      ENV["VERKILO_DOWNLOADS_STATS_TOKEN"].presence ||
        Rails.application.credentials.dig(:downloads, :stats_token)
    end

    # Daily buckets over the last `days` (Worker caps at 90 = AE retention).
    def fetch(days: 90)
      uri = URI(url)
      uri.query = URI.encode_www_form(bucket: "day", days:)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"

      response = Net::HTTP.start(uri.hostname, uri.port,
        use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise "downloads stats request failed: HTTP #{response.code} #{response.body}"
      end
      JSON.parse(response.body)
    end
  end
end
