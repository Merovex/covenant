require "test_helper"

class TicketMailerTest < ActionMailer::TestCase
  setup do
    @customer = customers(:ada)
    @ticket = Ticket.new(customer: @customer, title: "Cannot log in", creator: users(:system))
    @ticket.content = "<p>opener</p>"
    Record.originate(@ticket)
  end

  test "reply sets In-Reply-To to the last inbound message for client threading" do
    inbound = Reply.new(direction: :inbound, from_address: @customer.email,
      to_address: "support@x", message_id: "customer-abc@hey.com", creator: users(:system))
    inbound.content = "<p>help</p>"
    Record.originate(inbound, parent: @ticket.record)

    reply = Reply.new(direction: :outbound, from_address: "support@support.example.com",
      to_address: @customer.email, creator: users(:admin))
    reply.content = "<p>password reset</p>"
    Record.originate(reply, parent: @ticket.record)

    mail = TicketMailer.with(ticket: @ticket, reply: reply).reply

    assert_equal [ @customer.email ], mail.to
    assert_match "customer-abc@hey.com", mail.in_reply_to.to_s
    # We no longer set our own Message-ID — SES overwrites it; the controller
    # stores the SES-assigned id after delivery instead.
  end
end
