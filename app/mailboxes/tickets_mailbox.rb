# Ingests support mail. Precedence for placing a message (see
# docs/support-desk-plan.md and docs/decisions/0010-inbound-email-action-mailbox-ses.md):
#
#   1. Token embedded in a referenced Message-ID (In-Reply-To/References) →
#      the tamper-proof, authoritative route back to a ticket.
#   2. else a referenced Message-ID matches a stored Reply/Ticket id →
#      Strategy 2, recovers threads whose client dropped our token.
#   3. else open a new ticket (find-or-create the customer by From).
#
# No autoresponder: we deliberately never auto-reply to inbound mail. A new
# ticket's opener is often spam or a spoofed From, and auto-replying to a forged
# sender is backscatter that harms our sending reputation. Agents reply by hand.
#
# Idempotent: a redelivered notification (same Message-ID) is dropped before it
# can create a second row.
class TicketsMailbox < ApplicationMailbox
  # Our outbound Message-IDs look like <reply-<record_id>-<token>@domain>.
  TOKEN_PATTERN = /reply-\d+-([^@>]+)@/i

  def process
    return if already_ingested?

    record = locate_ticket_record
    ticket = record&.recordable

    ticket ? append_reply(ticket) : open_ticket
  end

  private
    def already_ingested?
      id = mail.message_id
      id.present? && (Reply.exists?(message_id: id) || Ticket.exists?(message_id: id))
    end

    def locate_ticket_record
      by_token || by_headers
    end

    # The token is authoritative: pull it straight out of any referenced
    # Message-ID and verify the signature. Survives even if we never stored the
    # outbound id.
    def by_token
      referenced_ids.each do |id|
        token = id[TOKEN_PATTERN, 1] or next
        record = Record.find_by_token_for(:ticket_reply, token)
        return record if record
      end
      nil
    end

    # Strategy 2 — recover replies whose client stripped the token by matching
    # the referenced Message-IDs against ids we've stored. An outbound reply's
    # Record parents to the ticket's Record; a ticket opener's Record is it.
    def by_headers
      ids = referenced_ids
      return if ids.empty?

      Reply.where(message_id: ids).first&.record&.parent ||
        Ticket.where(message_id: ids).first&.record
    end

    def referenced_ids
      (Array(mail.in_reply_to) + Array(mail.references)).flatten.compact.uniq
    end

    def append_reply(ticket)
      reply = Reply.new(direction: :inbound, from_address: sender_email,
        to_address: Array(mail.to).join(", "), subject: mail.subject,
        message_id: mail.message_id, in_reply_to: Array(mail.in_reply_to).first,
        creator: User.system)
      reply.content = body_html
      Record.originate(reply, parent: ticket.record)

      # The customer answered → the ball is back in our court. A pending ticket
      # (waiting on them) reopens so it resurfaces in the agent's queue.
      ticket.record.revise(event: :updated, status: :open) if ticket.pending?
    end

    def open_ticket
      ticket = Ticket.new(customer: customer, title: mail.subject.presence || "(no subject)",
        from_address: sender_email, message_id: mail.message_id, creator: User.system)
      ticket.content = body_html
      Record.originate(ticket)
    end

    def customer
      @customer ||= Customer.find_or_create_by!(email: sender_email) do |c|
        c.name = sender_name.presence || sender_email
      end
    end

    def sender_email
      @sender_email ||= (mail.from.is_a?(Array) ? mail.from.first : mail.from).to_s
    end

    def sender_name
      Mail::Address.new(mail[:from]&.value.to_s).display_name
    rescue StandardError
      nil
    end

    # Prefer the HTML part, fall back to plain text, then the bare body, and clean
    # it for storage: drop <style>/<script>/<head> (so an inlined stylesheet
    # doesn't leak in as text), fold the quoted reply history into a collapsed
    # <details>, and strip the sender's presentational cruft (HEY ships Trix's
    # .trix-content/.message-content wrappers + inline styles). ActionText
    # sanitizes whatever survives.
    def body_html
      part = mail.html_part || mail.text_part || mail
      raw = part.decoded.presence
      return "(no content)" unless raw
      return raw unless part.mime_type == "text/html"

      doc = Nokogiri::HTML(raw)
      doc.css("style, script, head, title, meta, link").remove
      collapse_quoted_reply(doc)
      doc.css("*").each { |el| %w[class style id].each { |a| el.remove_attribute(a) } }
      doc.at_css("body")&.inner_html.presence || "(no content)"
    end

    # Fold the quoted history a client appends on reply into a collapsed
    # <details> instead of deleting it — the thread already shows the history,
    # but keeping it (hidden) preserves context and any interleaved replying.
    # Replies are top-posted, so the history trails: cut at the "On … wrote:"
    # attribution, else the *last* top-level quote block, and move that node plus
    # everything after it into the disclosure. A blockquote the customer wrote
    # *above* the divider stays visible. <details> toggles natively — no JS.
    def collapse_quoted_reply(doc)
      body = doc.at_css("body") or return
      children = body.element_children

      cut = children.find { |el| el.text.to_s.match?(/\bwrote:\s*\z/i) }
      cut ||= children.reverse.find { |el| el.matches?("blockquote, .gmail_quote") || el.at_css("blockquote, .gmail_quote") }
      return unless cut

      quoted = [ cut ]
      quoted << quoted.last.next_element while quoted.last.next_element

      details = Nokogiri::XML::Node.new("details", doc)
      summary = Nokogiri::XML::Node.new("summary", doc)
      summary.content = "Quoted history"
      details.add_child(summary)
      quoted.each { |node| details.add_child(node) }
      body.add_child(details)
    end
end
