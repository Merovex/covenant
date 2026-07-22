# The agent reply composer on a ticket page: builds an outbound Reply version,
# threads it under the ticket's Record (parent:), and emails it to the
# customer. The Message-ID/token round-trip lives in TicketMailer.
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
      TicketMailer.with(ticket: @ticket, reply: @reply).reply.deliver_later
      redirect_to ticket_path(@record, anchor: "reply_#{@reply.record_id}"), notice: "Reply sent."
    else
      redirect_to ticket_path(@record, anchor: "new_reply"), alert: "Write a reply first."
    end
  end

  private
    def reply_params
      params.expect(reply: [ :content ])
    end
end
