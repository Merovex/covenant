require "test_helper"

class TicketsMailboxTest < ActionMailbox::TestCase
  setup { @customer = customers(:ada) }

  test "fresh mail opens a new ticket and finds the customer by From" do
    assert_difference -> { Ticket.current.count }, 1 do
      receive_inbound_email_from_mail(
        from: "Ada Lovelace <ada@example.com>", to: "support@support.example.com",
        subject: "Nothing loads", body: "<p>The page is blank.</p>")
    end

    ticket = Ticket.current.last
    assert_equal @customer, ticket.customer
    assert_equal "Nothing loads", ticket.title
    assert_equal users(:system), ticket.record.creator
  end

  test "an unknown sender is created as a customer" do
    assert_difference -> { Customer.count }, 1 do
      receive_inbound_email_from_mail(
        from: "New Person <new@example.com>", to: "support@support.example.com",
        subject: "Hello", body: "hi")
    end

    assert Customer.exists?(email: "new@example.com")
  end

  test "inbound HTML strips style/script so email CSS doesn't leak into the body" do
    html = '<html><head><style>.btn { color: #5522FA; } h1 { font-size: 1.3em; }</style>' \
           '</head><body><p>Real message here.</p><script>alert(1)</script></body></html>'

    receive_inbound_email_from_mail(
      from: "ada@example.com", to: "support@support.example.com",
      subject: "Styled", content_type: "text/html", body: html)

    text = Ticket.current.last.content.to_plain_text
    assert_includes text, "Real message here."
    assert_not_includes text, "5522FA"
    assert_not_includes text, "font-size"
    assert_not_includes text, "alert(1)"
  end

  test "a reply carrying our token threads onto the ticket" do
    ticket = open_ticket
    token = ticket.record.generate_token_for(:ticket_reply)
    our_mid = "<reply-#{ticket.record_id}-#{token}@support.example.com>"

    assert_difference -> { ticket.replies.count }, 1 do
      receive_inbound_email_from_mail(
        from: "ada@example.com", to: "support@support.example.com",
        subject: "Re: Broken", in_reply_to: our_mid, body: "<p>still broken</p>")
    end

    assert ticket.replies.last.inbound?
  end

  test "a message whose id already belongs to a reply is dropped (idempotent ingest)" do
    ticket = open_ticket
    # The mailbox stores mail.message_id, which the Mail gem returns WITHOUT
    # angle brackets — seed the same shape the ingest would.
    existing = Reply.new(direction: :inbound, from_address: "ada@example.com",
      to_address: "support@x", message_id: "dup@example.com", creator: users(:system))
    existing.content = "<p>first copy</p>"
    Record.originate(existing, parent: ticket.record)

    token = ticket.record.generate_token_for(:ticket_reply)
    our_mid = "<reply-#{ticket.record_id}-#{token}@support.example.com>"
    source = Mail.new(from: "ada@example.com", to: "support@support.example.com",
      subject: "Re: Broken", in_reply_to: our_mid, message_id: "<dup@example.com>",
      content_type: "text/html", body: "<p>again</p>").to_s

    assert_no_difference -> { Reply.count } do
      receive_inbound_email_from_source(source)
    end
  end

  private
    def open_ticket
      ticket = Ticket.new(customer: @customer, title: "Broken", creator: users(:system))
      ticket.content = "<p>opener</p>"
      Record.originate(ticket)
      ticket
    end
end
