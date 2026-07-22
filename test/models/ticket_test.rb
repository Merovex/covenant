require "test_helper"

class TicketTest < ActiveSupport::TestCase
  setup do
    @customer = customers(:ada)
    @system = users(:system)
  end

  def open_ticket(title: "Cannot log in", message_id: nil)
    ticket = Ticket.new(customer: @customer, title: title, creator: @system,
      from_address: @customer.email, message_id: message_id)
    ticket.content = "<p>I am locked out.</p>"
    Record.originate(ticket)
    ticket
  end

  test "defaults to open and appears in current" do
    ticket = open_ticket
    assert ticket.open?
    assert_includes Ticket.current, ticket
  end

  test "a status change versions and carries the opener forward" do
    ticket = open_ticket
    ticket.record.revise(event: :updated, status: "pending")

    current = ticket.record.recordable
    assert current.pending?
    assert_equal 2, ticket.record.versions.count
    assert_includes current.content.to_plain_text, "locked out"
  end

  test "replies returns current inbound and outbound versions in order" do
    ticket = open_ticket

    inbound = Reply.new(direction: :inbound, from_address: @customer.email,
      to_address: "support@x", creator: @system)
    inbound.content = "<p>still stuck</p>"
    Record.originate(inbound, parent: ticket.record)

    outbound = Reply.new(direction: :outbound, from_address: "support@x",
      to_address: @customer.email, creator: users(:admin))
    outbound.content = "<p>on it</p>"
    Record.originate(outbound, parent: ticket.record)

    assert_equal [ inbound, outbound ].map(&:record_id), ticket.replies.map(&:record_id)
  end
end
