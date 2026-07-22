class SessionsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access only: %i[new create verify]

  # Throttle magic-link requests to blunt enumeration/spam of the mailer.
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again later." }

  # Sign-in form: ask for an email address. On a fresh install (no real users
  # yet — the system account doesn't count) there's nothing to sign in to, so
  # send the first visitor to setup instead.
  def new
    redirect_to new_setup_path if User.people.none?
  end

  # Email a sign-in magic link to an existing user. Always reports success so we
  # don't leak which addresses have accounts. Registration happens elsewhere
  # (SetupsController / SignupsController), never here.
  def create
    if params[:email_address].present?
      code = User.with_email_address(params[:email_address])&.send_magic_link(purpose: :sign_in)
      expose_dev_sign_in_code(code)
    end

    redirect_to new_session_path(sent: true)
  end

  # Redeem the code from the emailed link (or from the manual entry form).
  def verify
    if (user = SignInCode.redeem(params[:code]))
      start_new_session_for user
      redirect_to after_authentication_url, notice: "You're signed in."
    else
      redirect_to new_session_path, alert: "That link is invalid or has expired."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: "You're signed out."
  end
end
