class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create verify]

  # Throttle magic-link requests to blunt enumeration/spam of the mailer.
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again later." }

  # Sign-in form: ask for an email address.
  def new
  end

  # Email a magic link. Always report success so we don't leak which addresses
  # have accounts. A user is created on first sign in (open registration).
  def create
    if params[:email_address].present?
      user = User.find_or_create_by(email_address: params[:email_address])
      if user.persisted?
        code, plaintext = SignInCode.generate_for(user)
        code.save!
        SessionMailer.magic_link(user, plaintext).deliver_later
      end
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
