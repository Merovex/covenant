# The support desk's people — a plain lookup-table CRUD (no spine ceremony),
# admin only. A customer with any license or ticket history can't be deleted
# (the model blocks it); rename instead.
class CustomersController < ApplicationController
  before_action -> { authorize! Customer, to: :manage }
  before_action :set_customer, only: %i[show edit update destroy]

  def index
    @customers = Customer.order(:name)
  end

  def show
    @licenses = @customer.licenses.merge(License.current).includes(:record)
    @tickets = @customer.tickets.merge(Ticket.current).includes(:record)
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
    def set_customer
      @customer = Customer.find(params[:id])
    end

    def customer_params
      params.expect(customer: [ :name, :email, :company, :notes ])
    end
end
