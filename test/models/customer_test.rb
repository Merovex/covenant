require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "requires name and email" do
    customer = Customer.new

    assert_not customer.valid?
    assert customer.errors[:name].any?
    assert customer.errors[:email].any?
  end

  test "normalizes and uniquely constrains email" do
    customer = Customer.create!(name: "New", email: "  NEW@Example.COM ")
    assert_equal "new@example.com", customer.email

    dupe = Customer.new(name: "Other", email: "new@example.com")
    assert_not dupe.valid?
    assert dupe.errors[:email].any?
  end

  test "cannot be destroyed while it owns tickets" do
    customer = customers(:ada)
    ticket = Ticket.new(customer: customer, title: "Hi", creator: users(:system))
    ticket.content = "<p>hello</p>"
    Record.originate(ticket)

    assert_not customer.destroy
    assert customer.errors[:base].any?
  end
end
