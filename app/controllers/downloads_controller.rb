# Staff-facing download analytics for the desktop app. Reads the local
# DownloadStat tally (mirrored hourly from the Cloudflare Worker) and presents
# it as running totals plus a daily breakdown. Admin only, like the rest of the
# support desk; a denial 404s (see the Authorization concern's philosophy).
class DownloadsController < ApplicationController
  before_action :require_admin

  DAILY_WINDOW = 14 # days shown in the day-by-day table

  def show
    today = Date.current

    @totals = {
      "Today"      => today..today,
      "This week"  => today.beginning_of_week..today,
      "This month" => today.beginning_of_month..today,
      "This year"  => today.beginning_of_year..today
    }.transform_values { |range| DownloadStat.total(range) }

    @month_by_platform = DownloadStat.by_platform(today.beginning_of_month..today)

    # Day × platform matrix for the recent window, newest day first.
    recent = DownloadStat.where(period: (today - (DAILY_WINDOW - 1))..today)
    @platforms = (recent.distinct.pluck(:platform).presence || %w[mac windows linux]).sort
    @daily = Hash.new { |rows, day| rows[day] = Hash.new(0) }
    recent.pluck(:period, :platform, :count).each { |day, platform, count| @daily[day][platform] += count }
    @daily = @daily.sort.reverse.to_h

    @last_synced = DownloadStat.maximum(:updated_at)
  end

  # Manual "Refresh" — pull from the Worker right now (admin action, so blocking
  # briefly is fine), then show the fresh numbers.
  def refresh
    DownloadStat.sync!
    redirect_to downloads_path, notice: "Download stats refreshed."
  rescue => e
    redirect_to downloads_path, alert: "Couldn't refresh download stats: #{e.message}"
  end

  private
    def require_admin
      render_not_found unless Current.user&.domain_admin?
    end
end
