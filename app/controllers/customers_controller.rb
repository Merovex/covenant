# The support desk's people — a plain lookup-table CRUD (no spine ceremony),
# admin only. A customer with any license or ticket history can't be deleted
# (the model blocks it); rename instead.
class CustomersController < ApplicationController
  before_action -> { authorize! Customer, to: :manage }
  before_action :set_customer, only: %i[show edit update destroy]

  def index
    # Customers holding a current license are "priority" — flagged with a key
    # and filterable via ?licensed.
    @licensed_ids = License.current.distinct.pluck(:customer_id).to_set
    @licensed = params[:licensed].present?
    scope = Customer.order(:name)
    scope = scope.where(id: @licensed_ids) if @licensed
    @customers = scope
  end

  # The customer's page: a glance row (license state, activations, money
  # paid, open tickets) over Tickets / Licenses / Orders panels. Tickets lead —
  # this is a support desk, and the question is usually "what's going on with
  # this person right now".
  def show
    @licenses = @customer.licenses.merge(License.current).includes(:record).order(:product)
    @tickets = @customer.tickets.merge(Ticket.current).includes(:record, :rich_text_content)
      .order(Arel.sql("tickets.record_id DESC"))
    @orders = @customer.orders.newest_first
    @reply_counts = Record.active.replies.where(parent_id: @tickets.map(&:record_id)).group(:parent_id).count
    @open_tickets = @tickets.count { |t| t.status.in?(%w[open pending on_hold]) }
    @glance = glance
    @last_activity = [ @customer.updated_at, *@tickets.map { |t| t.record.updated_at },
      *@licenses.map { |l| l.record.updated_at }, *@orders.map(&:updated_at) ].compact.max
  end

  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(customer_params)

    if @customer.save
      redirect_to @customer, notice: "Customer added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @customer.update(customer_params)
      redirect_to @customer, notice: "Customer saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @customer.destroy
      redirect_to customers_path, notice: "Customer deleted."
    else
      redirect_to @customer, alert: @customer.errors.full_messages.to_sentence
    end
  end

  private
    # The four at-a-glance figures. License = the best current status across
    # their licenses (active beats suspended beats expired/revoked); Paid = net
    # takings across their live orders, by currency.
    def glance
      status = %w[active suspended expired revoked].find { |s| @licenses.any? { |l| l.status == s } }
      external = @licenses.select(&:external?)
      used = external.sum(&:instances_count)
      limit = external.any? { |l| l.activation_limit.nil? } ? nil : external.sum { |l| l.activation_limit.to_i }
      paid = @orders.select(&:live?).select { |o| o.paid? || o.refunded? }
        .group_by(&:currency).map { |currency, orders| helpers.money(orders.sum(&:net_total), currency) }

      {
        "License"      => status&.titleize || "None",
        "Activations"  => external.any? ? "#{used} / #{limit || "∞"}" : "—",
        "Paid"         => paid.presence&.join(" · ") || helpers.money(0),
        "Open tickets" => @open_tickets.zero? ? "None" : @open_tickets
      }
    end

    def set_customer
      @customer = Customer.find(params[:id])
    end

    def customer_params
      params.expect(customer: [ :name, :email, :company ])
    end
end
