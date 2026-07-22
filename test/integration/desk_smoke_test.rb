require "test_helper"

class DeskSmokeTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:admin)) }

  test "customers index/new render" do
    get customers_path; assert_response :success
    get new_customer_path; assert_response :success
  end

  test "create a customer, license, ticket, and reply end to end" do
    post customers_path, params: { customer: { name: "Zed", email: "zed@example.com" } }
    customer = Customer.find_by(email: "zed@example.com")
    assert_redirected_to customer_path(customer)

    get new_license_path; assert_response :success
    post licenses_path, params: { license: { customer_id: customer.id, product: "Pro", license_key: "K-9", seats: 2 } }
    assert_response :redirect
    license = License.current.find_by(license_key: "K-9")
    assert license
    get licenses_path; assert_response :success
    get license_path(license.record); assert_response :success

    get new_ticket_path; assert_response :success
    post tickets_path, params: { ticket: { customer_id: customer.id, title: "Help me", content: "<p>broken</p>" } }
    ticket_record = Ticket.current.find_by(title: "Help me").record
    assert_redirected_to ticket_path(ticket_record)
    get ticket_path(ticket_record); assert_response :success

    # status transition
    patch ticket_path(ticket_record), params: { ticket: { status: "pending" } }
    assert ticket_record.reload.recordable.pending?

    # agent reply → sends mail now (so we can capture the SES Message-ID)
    assert_emails 1 do
      post ticket_replies_path(ticket_record), params: { reply: { content: "<p>on it</p>" } }
    end
    assert_equal 1, ticket_record.recordable.replies.count
    assert ticket_record.recordable.replies.first.outbound?
    get tickets_path; assert_response :success
  end

  test "non-admin is denied the desk (404)" do
    sign_in_as(users(:alice))
    get tickets_path; assert_response :not_found
    get customers_path; assert_response :not_found
    get licenses_path; assert_response :not_found
  end
end
