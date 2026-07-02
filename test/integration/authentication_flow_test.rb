require "test_helper"

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "protected pages redirect to sign in when unauthenticated" do
    get root_path # public styleguide is allowed
    assert_response :success
  end

  test "full magic-link sign in, then sign out" do
    # Request a link for a brand-new address (open registration).
    email = perform_enqueued_jobs do
      assert_difference "User.count", 1 do
        post session_path, params: { email_address: "newcomer@example.com" }
      end
      ActionMailer::Base.deliveries.last
    end
    assert_redirected_to new_session_path(sent: true)
    assert_equal ["newcomer@example.com"], email.to

    # Recover the plaintext code from the emailed link (only place it exists).
    plaintext = email.body.encoded[/code=([A-Z]{8})/, 1]
    assert_match(/\A[A-Z]{8}\z/, plaintext)

    # Redeem it as the emailed link would.
    get verify_session_path(code: plaintext)
    assert_redirected_to root_url
    assert_equal 1, Session.count

    # The authenticated header renders (avatar initials + sign-out control).
    follow_redirect!
    assert_response :success
    assert_select "button.avatar", text: "NE"

    # Sign out.
    delete session_path
    assert_redirected_to new_session_path
    assert_equal 0, Session.count
  end

  test "invalid code does not sign in" do
    get verify_session_path(code: "ZZZZZZZZ")
    assert_redirected_to new_session_path
    assert_equal 0, Session.count
  end
end
