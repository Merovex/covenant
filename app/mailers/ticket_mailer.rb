# Support-desk outbound mail. Threading follows the 37signals / Help Scout
# pattern (see docs/support-desk-plan.md): a clean support@ From, no Reply-To,
# no plus-addressing — the routing key is a tamper-proof token embedded in OUR
# Message-ID. The customer's client echoes that Message-ID into
# In-Reply-To/References on reply, and TicketsMailbox reads it back to thread.
class TicketMailer < ApplicationMailer
  # An agent's reply to the customer. Carries the tokenised Message-ID and, when
  # there's a prior inbound message, standard In-Reply-To/References so the
  # customer's client keeps the thread. Persists the sent Message-ID on the
  # Reply so Strategy-2 header matching can recover the thread later.
  def reply
    @ticket = params[:ticket]
    @reply  = params[:reply]

    mail to: @ticket.customer.email, subject: "Re: #{@ticket.title}"

    token = @ticket.record.generate_token_for(:ticket_reply)
    message.message_id = "reply-#{@ticket.record_id}-#{token}@#{ApplicationMailer.inbound_domain}"

    if (parent = @ticket.replies.where(direction: :inbound).last&.message_id)
      message.header["In-Reply-To"] = parent
      message.header["References"]  = parent
    end

    @reply.update_column(:message_id, message.message_id) if @reply&.persisted?
  end
end
