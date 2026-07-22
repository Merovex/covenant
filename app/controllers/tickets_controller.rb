# Support tickets on the spine — the agent's queue. Index lists current live
# tickets; show is the opener plus the reply thread and a composer. Immutable
# like every recordable: status changes and edits are versions, delete trashes
# the history. Admin only.
class TicketsController < ApplicationController
  include TicketScoped
  skip_before_action :set_record, only: %i[index new create]
  before_action -> { authorize! Ticket, to: :manage }

  def index
    @status = params[:status] if params[:status].in?(Ticket.statuses.keys)
    # Remember the filter so a ticket's "Tickets" breadcrumb returns to it
    # ("all" when unfiltered). Defaults to open on a first visit (see helper).
    session[:tickets_filter] = @status || "all"
    @status_counts = Ticket.current.group(:status).count

    scope = Ticket.current.includes(:record, :customer, :rich_text_content)
    scope = scope.where(status: @status) if @status
    @tickets = scope.order(Arel.sql("tickets.record_id DESC"))

    @reply_counts = Record.active.replies
      .where(parent_id: @tickets.map(&:record_id)).group(:parent_id).count
  end

  def show
    # Context panel: the customer's other tickets — their 3 most recent, or all
    # opened in the last 30 days, whichever is the larger set.
    others = Ticket.current
      .where(customer_id: @ticket.customer_id).where.not(record_id: @record.id)
      .includes(:record, :rich_text_content).order(record_id: :desc).limit(50).to_a
    recent = others.select { |t| t.record.created_at >= 30.days.ago }
    @related_tickets = recent.size >= 3 ? recent : others.first(3)
  end

  def new
    @ticket = Ticket.new(customer_id: params[:customer_id])
  end

  # An agent opening a ticket in-app: the first message is the opener, exactly
  # like a customer's inbound email. No autoresponder — that's inbound only.
  def create
    @ticket = Ticket.new(ticket_params.merge(event: :created))

    if @ticket.valid?
      Record.originate(@ticket)
      redirect_to ticket_path(@ticket.record), notice: "Ticket opened."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Handles both the status buttons (status only) and the edit form
  # (title/customer): revise applies whatever changed and carries the rest
  # forward. The opener (`:content`) is deliberately excluded — the customer's
  # original message is immutable; it's only ever set at creation time.
  def update
    @ticket = @record.revise(event: :updated, **ticket_params.except(:content).to_h.symbolize_keys)

    if @ticket.errors.none?
      redirect_to ticket_path(@record), notice: "Ticket updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.trash
    redirect_to tickets_path, notice: "Ticket moved to trash."
  end

  private
    def ticket_params
      params.expect(ticket: [ :customer_id, :title, :status, :content ])
    end
end
