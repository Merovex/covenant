require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "with_email_address finds an existing user regardless of casing/whitespace" do
    assert_equal users(:alice), User.with_email_address("  ALICE@example.com ")
    assert_nil User.with_email_address("nobody@example.com")
  end

  test "send_magic_link creates one single-use code and enqueues one email" do
    alice = users(:alice)

    assert_difference -> { alice.sign_in_codes.count }, 1 do
      assert_enqueued_emails 1 do
        alice.send_magic_link(for: :sign_in)
      end
    end
  end

  test "registration policy reflects configuration" do
    assert_equal :invite_only, User.registration_policy
    assert_not User.registration_open?

    with_registration_policy :open do
      assert User.registration_open?
    end
  end
end
