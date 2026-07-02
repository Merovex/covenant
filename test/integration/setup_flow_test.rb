require "test_helper"

class SetupFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "with users already present, setup is unavailable" do
    get new_setup_path
    assert_redirected_to root_path

    post setup_path, params: { setup: { email_address: "someone@example.com" } }
    assert_redirected_to root_path
  end

  test "on a fresh install, the sign-in screen sends you to setup" do
    User.delete_all
    get new_session_path
    assert_redirected_to new_setup_path
  end

  test "the first visitor sets up the install and becomes domain admin" do
    User.delete_all

    get new_setup_path
    assert_response :success
    assert_select "main.auth" # centered auth layout, no app chrome

    assert_difference "User.count", 1 do
      assert_enqueued_emails 1 do
        post setup_path, params: { setup: { email_address: "founder@example.com" } }
      end
    end
    assert_redirected_to new_session_path(sent: true)

    assert User.find_by(email_address: "founder@example.com").domain_admin?
  end

  test "setup rejects an invalid email without creating a user" do
    User.delete_all

    assert_no_difference "User.count" do
      post setup_path, params: { setup: { email_address: "not-an-email" } }
    end
    assert_response :unprocessable_entity
  end
end
