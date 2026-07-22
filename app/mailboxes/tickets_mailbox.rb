# Ingests support mail. Precedence for placing a message (see
# docs/support-desk-plan.md and docs/decisions/0010-inbound-email-action-mailbox-ses.md):
#
#   1. Token embedded in a referenced Message-ID (In-Reply-To/References) →
#      the tamper-proof, authoritative route back to a ticket.
#   2. else a referenced Message-ID matches a stored Reply/Ticket id →
#      Strategy 2, recovers threads whose client dropped our token.
#   3. else open a new ticket (find-or-create the customer by From) and fire
#      the acknowledgement autoresponder.
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
    end

    def open_ticket
      ticket = Ticket.new(customer: customer, title: mail.subject.presence || "(no subject)",
        from_address: sender_email, message_id: mail.message_id, creator: User.system)
      ticket.content = body_html
      Record.originate(ticket)

      TicketMailer.with(ticket: ticket).acknowledgement.deliver_later
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

    # Prefer the HTML part, fall back to plain text, then the bare body.
    def body_html
      part = mail.html_part || mail.text_part || mail
      part.decoded.presence || "(no content)"
    end
end
