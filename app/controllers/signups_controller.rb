# Open self-registration. Reachable only when the registration policy is :open;
# otherwise sign-in is the only way in (invite-only).
class SignupsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access
  before_action :require_open_registration

  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_signup_path, alert: "Too many attempts. Try again later." }

  def new
    @signup = Signup.new
  end

  def create
    @signup = Signup.new(signup_params)
    if @signup.save
      redirect_to new_session_path(sent: true)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def require_open_registration
    redirect_to new_session_path unless User.registration_open?
  end

  def signup_params
    params.expect(signup: :email_address)
  end
end
