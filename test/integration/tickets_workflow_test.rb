require "test_helper"

class TicketsWorkflowTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  def open_ticket
    ticket = Ticket.new(customer: customers(:ada), title: "Broken", creator: users(:system))
    ticket.content = "<p>original message</p>"
    Record.originate(ticket)
    ticket
  end

  test "replying to a customer sets the ticket to pending" do
    ticket = open_ticket
    assert ticket.open?

    post ticket_replies_path(ticket.record), params: { reply: { content: "<p>here's a fix</p>" } }

    assert ticket.record.reload.recordable.pending?
  end

  test "updating a ticket never rewrites the original message" do
    ticket = open_ticket

    patch ticket_path(ticket.record), params: { ticket: { title: "Renamed", content: "<p>TAMPERED</p>" } }

    current = ticket.record.reload.recordable
    assert_equal "Renamed", current.title
    assert_includes current.content.to_plain_text, "original message"
    assert_not_includes current.content.to_plain_text, "TAMPERED"
  end

  test "show renders status actions in the head and offers no Edit" do
    ticket = open_ticket
    get ticket_path(ticket.record)

    assert_response :success
    assert_select "a", text: "Edit", count: 0
    assert_select "button", text: "Resolved"
    assert_select "button", text: "Hold"
  end

  test "show lists the customer's other tickets in the context panel, excluding itself" do
    ticket = open_ticket # customers(:ada), title "Broken"
    other = Ticket.new(customer: customers(:ada), title: "Another issue", creator: users(:system))
    other.content = "<p>x</p>"
    Record.originate(other)

    get ticket_path(ticket.record)

    assert_response :success
    assert_select ".ticket__related-link", text: "Another issue"
    assert_select ".ticket__related-link", text: "Broken", count: 0
  end

  test "the Resolved button resolves and stamps resolved_at" do
    ticket = open_ticket

    patch ticket_path(ticket.record), params: { ticket: { status: "resolved" } }

    current = ticket.record.reload.recordable
    assert current.resolved?
    assert_not_nil current.resolved_at
  end
end
