require "test_helper"

class ReplyTest < ActiveSupport::TestCase
  setup do
    @customer = customers(:ada)
    @system = users(:system)
    @ticket = Ticket.new(customer: @customer, title: "Help", creator: @system)
    @ticket.content = "<p>opener</p>"
    Record.originate(@ticket)
  end

  test "an inbound reply threads under the ticket and resolves back" do
    reply = Reply.new(direction: :inbound, from_address: @customer.email,
      to_address: "support@x", creator: @system)
    reply.content = "<p>more info</p>"
    Record.originate(reply, parent: @ticket.record)

    assert_equal @ticket.record, reply.record.parent
    assert_equal @ticket, reply.ticket
  end

  test "requires direction, addresses and content" do
    reply = Reply.new

    assert_not reply.valid?
    assert reply.errors[:direction].any?
    assert reply.errors[:from_address].any?
    assert reply.errors[:to_address].any?
    assert reply.errors[:content].any?
  end

  test "inbound mail is authored by the system user" do
    reply = Reply.new(direction: :inbound, from_address: @customer.email,
      to_address: "support@x", creator: User.system)
    reply.content = "<p>hi</p>"
    Record.originate(reply, parent: @ticket.record)

    assert reply.persisted?
    assert reply.creator.system?
    assert reply.record.creator.system?
  end
end
