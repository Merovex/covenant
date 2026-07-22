# Support-desk outbound mail: a clean support@ From (see ADR 0010).
#
# Threading anchor — the SES-assigned Message-ID. We deliberately do NOT set our
# own Message-ID: Amazon SES *overwrites* it with its own on send (proven in the
# field — a customer reply's In-Reply-To was `…@email.amazonses.com`, not our
# token). So the routing key is the Message-ID SES assigns; it's captured right
# after delivery and stored on the Reply (Tickets::RepliesController#create).
# The customer's client echoes that id into In-Reply-To/References, and
# TicketsMailbox matches it back to the reply to thread.
class TicketMailer < ApplicationMailer
  # An agent's reply to the customer. Sets In-Reply-To/References to the last
  # inbound message so the customer's client keeps the visual thread.
  def reply
    @ticket = params[:ticket]
    @reply  = params[:reply]

    mail to: @ticket.customer.email, subject: "Re: #{@ticket.title}"

    if (parent = @ticket.replies.where(direction: :inbound).last&.message_id)
      message.header["In-Reply-To"] = parent
      message.header["References"]  = parent
    end
  end
end
