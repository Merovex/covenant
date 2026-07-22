require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  def open_ticket(title:, status: :open)
    ticket = Ticket.new(customer: customers(:ada), title: title, creator: users(:system))
    ticket.content = "<p>#{title}</p>"
    Record.originate(ticket)
    ticket.record.revise(event: :updated, status: status.to_s) unless status == :open
    ticket
  end

  test "admin dashboard lists only open tickets, with links to other queues" do
    open_ticket(title: "Login broken", status: :open)
    open_ticket(title: "Waiting on them", status: :pending)
    open_ticket(title: "Blocked upstream", status: :on_hold)

    sign_in_as users(:admin)
    get root_path

    assert_response :success
    assert_select ".dashboard__stats .dashboard__stat", 4          # new-license counters
    assert_select ".list .list__title", text: "Login broken"      # the open one shows
    assert_select ".list .list__title", text: "Waiting on them", count: 0
    assert_select ".list .list__title", text: "Blocked upstream", count: 0
    assert_select "a[href=?]", tickets_path(status: "pending")     # filter links present
    assert_select "a[href=?]", tickets_path(status: "on_hold")
  end

  test "new-license counts reflect what was created in each window" do
    License.new(customer: customers(:ada), license_key: "TODAY-1", product: "Pro",
      creator: users(:admin)).then { |l| Record.originate(l) }

    sign_in_as users(:admin)
    get root_path

    assert_select ".dashboard__stats .dashboard__stat:first-child .dashboard__stat-number", "1"
  end

  test "non-admins get no support content" do
    sign_in_as users(:alice)
    get root_path

    assert_response :success
    assert_select ".dashboard__stats", count: 0
    assert_select ".list", count: 0
  end

  test "the sign-in code is never exposed outside development" do
    post session_path, params: { email_address: users(:alice).email_address }

    assert_nil flash[:sign_in_code]
  end
end
