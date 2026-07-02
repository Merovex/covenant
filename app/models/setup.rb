# First-run install setup: creates the very first user as domain admin and sends
# them a sign-up magic link. Only ever reachable when no users exist yet (see
# SetupsController#require_no_users), so there's no policy check here.
class Setup
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email_address, :string

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  attr_reader :user

  def save
    return false unless valid?

    @user = User.new(email_address: email_address, role: :domain_admin)
    if @user.save
      @user.send_magic_link(for: :sign_up)
      true
    else
      errors.merge!(@user.errors)
      false
    end
  end
end
