require "test_helper"

class TicketsFilterTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  def open_ticket(title:, status: :open)
    ticket = Ticket.new(customer: customers(:ada), title: title, creator: users(:system))
    ticket.content = "<p>#{title}</p>"
    Record.originate(ticket)
    ticket.record.revise(event: :updated, status: status.to_s) unless status == :open
    ticket
  end

  test "the index filters by a valid status and ignores a bogus one" do
    open_ticket(title: "Open one", status: :open)
    open_ticket(title: "On-hold one", status: :on_hold)

    get tickets_path(status: "on_hold")
    assert_select ".list__title", text: "On-hold one"
    assert_select ".list__title", text: "Open one", count: 0

    # A bogus status falls back to showing everything.
    get tickets_path(status: "nonsense")
    assert_select ".list__title", text: "Open one"
    assert_select ".list__title", text: "On-hold one"
  end
end
