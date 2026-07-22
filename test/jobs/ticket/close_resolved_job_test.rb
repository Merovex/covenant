require "test_helper"

class Ticket::CloseResolvedJobTest < ActiveJob::TestCase
  setup do
    @customer = customers(:ada)
    @system = users(:system)
  end

  # Opens a ticket, resolves it, then backdates resolved_at to simulate age.
  def resolved_ticket(resolved_at:)
    ticket = Ticket.new(customer: @customer, title: "x", creator: @system, from_address: @customer.email)
    ticket.content = "<p>hi</p>"
    Record.originate(ticket)
    version = ticket.record.revise(event: :updated, status: "resolved")
    version.update_column(:resolved_at, resolved_at)
    ticket.record
  end

  test "closes tickets resolved at least a week ago and leaves fresher ones" do
    stale = resolved_ticket(resolved_at: 8.days.ago)
    fresh = resolved_ticket(resolved_at: 2.days.ago)

    Ticket::CloseResolvedJob.perform_now

    assert stale.reload.recordable.closed?, "week-old resolved ticket should be closed"
    assert fresh.reload.recordable.resolved?, "recently resolved ticket should stay resolved"
  end
end
