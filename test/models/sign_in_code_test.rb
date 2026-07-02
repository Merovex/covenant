require "test_helper"

class SignInCodeTest < ActiveSupport::TestCase
  setup { @user = users(:alice) }

  test "generate_for produces an 8-letter code and stores only its digest" do
    code, plaintext = SignInCode.generate_for(@user)

    assert_match(/\A[A-Z]{8}\z/, plaintext)
    assert_equal SignInCode.digest(plaintext), code.code_digest
    assert_not_includes code.code_digest, plaintext
    assert code.expires_at > Time.current
  end

  test "format groups the code as ABCD-EFGH" do
    assert_equal "ABCD-EFGH", SignInCode.format("ABCDEFGH")
  end

  test "redeem returns the user and consumes the code (dashes/case forgiven)" do
    code, plaintext = SignInCode.generate_for(@user)
    code.save!

    assert_equal @user, SignInCode.redeem(SignInCode.format(plaintext).downcase)
    assert code.reload.consumed_at.present?
  end

  test "a code cannot be redeemed twice" do
    code, plaintext = SignInCode.generate_for(@user)
    code.save!

    assert_equal @user, SignInCode.redeem(plaintext)
    assert_nil SignInCode.redeem(plaintext)
  end

  test "expired codes are not redeemable" do
    code, plaintext = SignInCode.generate_for(@user)
    code.update!(expires_at: 1.minute.ago)

    assert_nil SignInCode.redeem(plaintext)
  end

  test "malformed input is rejected without a query" do
    assert_nil SignInCode.redeem("not-a-code")
    assert_nil SignInCode.redeem("")
    assert_nil SignInCode.redeem(nil)
  end
end
