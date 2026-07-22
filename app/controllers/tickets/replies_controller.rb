# The agent reply composer on a ticket page: builds an outbound Reply version,
# threads it under the ticket's Record (parent:), emails it, and records the
# SES-assigned Message-ID so the customer's eventual reply threads back.
class Tickets::RepliesController < ApplicationController
  include TicketScoped
  before_action -> { authorize! Ticket, to: :manage }

  def create
    @reply = Reply.new(reply_params.merge(direction: :outbound, event: :created,
      from_address: "support@#{ApplicationMailer.inbound_domain}",
      to_address: @ticket.customer.email, subject: "Re: #{@ticket.title}",
      creator: Current.user))

    if @reply.valid?
      Record.originate(@reply, parent: @record)
      # Replying hands the ball back to the customer → the ticket is now Pending
      # (waiting on them), unless it already is. A plain revise on the spine.
      @record.revise(event: :updated, status: :pending) unless @ticket.pending?
      deliver_reply(@reply)
      redirect_to ticket_path(@record, anchor: "reply_#{@reply.record_id}"), notice: "Reply sent."
    else
      redirect_to ticket_path(@record, anchor: "new_reply"), alert: "Write a reply first."
    end
  end

  private
    def reply_params
      params.expect(reply: [ :content ])
    end

    # Send now (not later) so we can read the Message-ID SES assigns — SES
    # rewrites any id we set, and its id is what the customer's client echoes in
    # In-Reply-To. Storing it lets TicketsMailbox thread the reply back (ADR 0010).
    # A send failure leaves the reply saved but unthreadable; we don't 500 the agent.
    def deliver_reply(reply)
      message = TicketMailer.with(ticket: @ticket, reply: reply).reply.deliver_now
      ses_id = message["ses_message_id"]&.value
      reply.update_column(:message_id, "#{ses_id}@email.amazonses.com") if ses_id.present?
    rescue => e
      Rails.logger.error("[TicketMailer] reply send failed: #{e.class}: #{e.message}")
    end
end
