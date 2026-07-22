class SessionMailer < ApplicationMailer
  # Auth mail sends from the transactional From (noreply@…), not the support
  # desk's support@ default that ApplicationMailer sets.
  default from: -> { ApplicationMailer.transactional_from }

  SUBJECTS = {
    sign_in: "Your Verkilo sign-in link",
    sign_up: "Welcome to Verkilo — confirm your email"
  }.freeze

  # Emails a magic-link sign-in code. `plaintext` is the raw 8-letter code; it
  # lives only in this email — the database stores only its digest. `purpose`
  # (:sign_in / :sign_up) just tunes the subject line.
  def magic_link(user, plaintext, purpose: :sign_in)
    @user = user
    @code = plaintext
    @formatted_code = SignInCode.format(plaintext)
    @verify_url = verify_session_url(code: plaintext)

    mail to: user.email_address, subject: SUBJECTS.fetch(purpose, SUBJECTS[:sign_in])
  end
end
