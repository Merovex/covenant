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

  test "a reply referencing a stored (SES-assigned) outbound Message-ID threads via headers" do
    ticket = open_ticket
    # SES rewrites our Message-ID, so we store the id SES assigned; the customer's
    # client echoes it in In-Reply-To, and header matching recovers the thread.
    ses_mid = "0100dead-beef-000000@email.amazonses.com"
    outbound = Reply.new(direction: :outbound, from_address: "support@x",
      to_address: @customer.email, message_id: ses_mid, creator: users(:admin))
    outbound.content = "<p>try this</p>"
    Record.originate(outbound, parent: ticket.record)

    assert_difference -> { ticket.replies.count }, 1 do
      receive_inbound_email_from_mail(
        from: @customer.email, to: "support@support.example.com",
        subject: "Re: Broken", in_reply_to: "<#{ses_mid}>", body: "<p>didn't work</p>")
    end

    assert ticket.replies.last.inbound?
  end

  test "the trailing quoted history folds into a collapsed <details>, kept not deleted" do
    html = "<html><body>" \
           "<div>My fresh answer.</div>" \
           "<div>On July 22, 2026, Verkilo Support wrote:</div>" \
           "<blockquote><p>the previous message</p></blockquote>" \
           "</body></html>"

    receive_inbound_email_from_mail(from: "ada@example.com", to: "support@support.example.com",
      subject: "Re: Broken", content_type: "text/html", body: html)

    doc = Nokogiri::HTML(Ticket.current.last.content.body.to_html)
    details = doc.at_css("details")
    assert details, "expected the quoted history folded into a <details>"
    assert_includes details.text, "the previous message"     # kept, just collapsed
    assert_not_includes details.text, "My fresh answer."      # the new reply stays visible
  end

  test "a blockquote the customer wrote above the divider stays visible" do
    html = "<html><body>" \
           "<blockquote><p>my intentional quote</p></blockquote>" \
           "<div>my point about it</div>" \
           "<div>On July 22, 2026, Verkilo Support wrote:</div>" \
           "<blockquote><p>old history</p></blockquote>" \
           "</body></html>"

    receive_inbound_email_from_mail(from: "ada@example.com", to: "support@support.example.com",
      subject: "Re: Broken", content_type: "text/html", body: html)

    details = Nokogiri::HTML(Ticket.current.last.content.body.to_html).at_css("details")
    assert_includes details.text, "old history"
    assert_not_includes details.text, "my intentional quote"
    assert_not_includes details.text, "my point about it"
  end

  test "a customer reply reopens a pending ticket" do
    ticket = open_ticket
    ticket.record.revise(event: :updated, status: "pending")

    ses_mid = "0100abcd-0000@email.amazonses.com"
    outbound = Reply.new(direction: :outbound, from_address: "support@x", to_address: @customer.email,
      message_id: ses_mid, creator: users(:admin))
    outbound.content = "<p>hi</p>"
    Record.originate(outbound, parent: ticket.record)

    receive_inbound_email_from_mail(from: @customer.email, to: "support@support.example.com",
      subject: "Re: Broken", in_reply_to: "<#{ses_mid}>", body: "<p>thanks</p>")

    assert ticket.record.reload.recordable.open?
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
