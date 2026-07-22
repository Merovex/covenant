require "test_helper"

class TicketMailerTest < ActionMailer::TestCase
  setup do
    @customer = customers(:ada)
    @ticket = Ticket.new(customer: @customer, title: "Cannot log in", creator: users(:system))
    @ticket.content = "<p>opener</p>"
    Record.originate(@ticket)
  end

  test "reply embeds a tamper-proof token in the Message-ID and persists it" do
    reply = Reply.new(direction: :outbound, from_address: "support@support.example.com",
      to_address: @customer.email, creator: users(:admin))
    reply.content = "<p>password reset</p>"
    Record.originate(reply, parent: @ticket.record)

    mail = TicketMailer.with(ticket: @ticket, reply: reply).reply
    mail.message_id # force the deferred headers/render

    token = mail.message_id[/reply-\d+-([^@]+)@/, 1]
    assert_equal @ticket.record, Record.find_by_token_for(:ticket_reply, token)
    assert_equal mail.message_id, reply.reload.message_id
  end
end
