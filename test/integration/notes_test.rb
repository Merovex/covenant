require "test_helper"

class NotesTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "saves a rich-text note on a customer" do
    customer = customers(:ada)

    patch note_path, params: {
      sgid: customer.to_sgid(for: "note").to_s, notable: { note: "<p>VIP — handle fast</p>" }
    }

    assert_includes customer.reload.note.to_plain_text, "VIP"
  end

  test "saves a note on a ticket's stable Record (survives versioning)" do
    ticket = Ticket.new(customer: customers(:ada), title: "x", creator: users(:system))
    ticket.content = "<p>o</p>"
    Record.originate(ticket)

    patch note_path, params: {
      sgid: ticket.record.to_sgid(for: "note").to_s, notable: { note: "<p>watch this one</p>" }
    }
    # a later status change must not lose the note (it lives on the Record)
    ticket.record.revise(event: :updated, status: "pending")

    assert_includes ticket.record.reload.note.to_plain_text, "watch this one"
  end

  test "a forged or garbage sgid is rejected" do
    patch note_path, params: { sgid: "garbage", notable: { note: "<p>x</p>" } }
    assert_response :not_found
  end
end
