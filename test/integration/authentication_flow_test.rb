require "test_helper"

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "protected pages redirect to sign in when unauthenticated" do
    get root_path # public styleguide is allowed
    assert_response :success
  end

  test "sign-in screen uses the centered auth layout, not the app canvas" do
    get new_session_path
    assert_response :success
    assert_select "main.auth"
    assert_select "header.app-header", false
    assert_select "main.canvas", false
  end

  test "check-your-email state renders the segmented eight-box code input" do
    get new_session_path(sent: true)
    assert_response :success
    assert_select ".code-input[data-controller=?]", "code-field"
    assert_select ".code-input input.code-input__box", 8
    assert_select ".code-input input[type=hidden][name=code][data-code-field-target=hidden]"
    assert_select ".code-input__sep", 1                         # single 4+4 divider
    assert_select "input.code-input__box[autofocus]", 1          # only the first box
    assert_select "input.code-input__box[data-action*=?]", "code-field#onPaste"
  end

  test "an existing user completes magic-link sign in, then signs out" do
    alice = users(:alice)

    # Sign-in never registers — alice already exists.
    email = perform_enqueued_jobs do
      assert_no_difference "User.count" do
        post session_path, params: { email_address: alice.email_address }
      end
      ActionMailer::Base.deliveries.last
    end
    assert_redirected_to new_session_path(sent: true)
    assert_equal [ alice.email_address ], email.to

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
    assert_select "button.avatar", text: "AE"

    # Sign out.
    delete session_path
    assert_redirected_to new_session_path
    assert_equal 0, Session.count
  end

  test "sign-in for an unknown address: no account, no email, and no leak" do
    assert_no_difference [ "User.count", "SignInCode.count" ] do
      assert_no_enqueued_emails do
        post session_path, params: { email_address: "stranger@example.com" }
      end
    end
    # Still reports success so we don't reveal who does/doesn't have an account.
    assert_redirected_to new_session_path(sent: true)
  end

  test "invalid code does not sign in" do
    get verify_session_path(code: "ZZZZZZZZ")
    assert_redirected_to new_session_path
    assert_equal 0, Session.count
  end
end
