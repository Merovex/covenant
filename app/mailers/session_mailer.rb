class SessionMailer < ApplicationMailer
  # Emails a magic-link sign-in code. `plaintext` is the raw 8-letter code; it
  # lives only in this email — the database stores only its digest.
  def magic_link(user, plaintext)
    @user = user
    @code = plaintext
    @formatted_code = SignInCode.format(plaintext)
    @verify_url = verify_session_url(code: plaintext)

    mail to: user.email_address, subject: "Your Alcovo sign-in link"
  end
end
