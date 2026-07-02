# Open self-registration: registers a new member (or reuses an existing account)
# and sends a sign-up magic link. Only reachable when registration is open (see
# SignupsController#require_open_registration).
class Signup
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email_address, :string

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  attr_reader :user

  def save
    return false unless valid?

    @user = User.with_email_address(email_address) || User.new(email_address: email_address)
    if @user.persisted? || @user.save
      @user.send_magic_link(for: :sign_up)
      true
    else
      errors.merge!(@user.errors)
      false
    end
  end
end
