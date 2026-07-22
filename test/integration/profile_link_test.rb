require "test_helper"
class ProfileLinkTest < ActionDispatch::IntegrationTest
  test "the account menu links My Profile to the profile page" do
    sign_in_as users(:alice)
    get root_path
    assert_select ".menu--user a[href=?]", user_settings_path, text: "My Profile"
    get user_settings_path
    assert_select "h1.perma-header__title", "My Profile"
    assert_select "input[name='user[name]']"
    assert_select ".settings__avatar input[type=file]"
  end
end
