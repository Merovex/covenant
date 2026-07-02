require "test_helper"

class SignupFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "invite-only (default): signup is unavailable" do
    get new_signup_path
    assert_redirected_to new_session_path

    post signup_path, params: { signup: { email_address: "newcomer@example.com" } }
    assert_redirected_to new_session_path
  end

  test "open: a new visitor registers as a member and is emailed a link" do
    with_registration_policy :open do
      get new_signup_path
      assert_response :success

      assert_difference "User.count", 1 do
        assert_enqueued_emails 1 do
          post signup_path, params: { signup: { email_address: "newcomer@example.com" } }
        end
      end
      assert_redirected_to new_session_path(sent: true)
    end

    assert User.find_by(email_address: "newcomer@example.com").member?
  end

  test "open: signing up an already-registered address emails a link without duplicating" do
    with_registration_policy :open do
      assert_no_difference "User.count" do
        assert_enqueued_emails 1 do
          post signup_path, params: { signup: { email_address: users(:alice).email_address } }
        end
      end
      assert_redirected_to new_session_path(sent: true)
    end
  end
end
