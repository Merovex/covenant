# The authenticated home at root: a landing dashboard onto the support desk.
# Behind sign-in like everything else (ApplicationController enforces it). The
# generic Alcovo-template sections (posts/forum/chatroom) are intentionally not
# surfaced here — this install is a support desk.
class DashboardController < ApplicationController
  def show
    return unless Current.user.domain_admin?

    @license_stats = new_license_counts
    @status_counts = Ticket.current.group(:status).count
    @open_tickets = Ticket.current.open
      .includes(:record, :customer, :rich_text_content)
      .order(Arel.sql("tickets.record_id DESC"))
  end

  private

  # Licenses created within each window, counted off the spine Record (its
  # created_at is when the license came into being; later versions don't move
  # it). Cumulative-from-start buckets: "this week" includes today, and so on.
  def new_license_counts
    now = Time.current
    scope = Record.active.licenses
    {
      "Today"      => scope.where(created_at: now.beginning_of_day..).count,
      "This week"  => scope.where(created_at: now.beginning_of_week..).count,
      "This month" => scope.where(created_at: now.beginning_of_month..).count,
      "This year"  => scope.where(created_at: now.beginning_of_year..).count
    }
  end
end
