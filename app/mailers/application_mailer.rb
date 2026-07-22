class ApplicationMailer < ActionMailer::Base
  default from: -> { "Covenant Support <support@#{ApplicationMailer.inbound_domain}>" }
  layout "mailer"

  # The domain the support desk receives mail on (SES inbound receipt rule) and
  # sends replies from. Sourced from credentials/ENV so it's a single knob;
  # falls back to a dev-safe default until SES is wired up (see
  # docs/decisions/0010-inbound-email-action-mailbox-ses.md).
  def self.inbound_domain
    Rails.application.credentials.dig(:support, :inbound_domain) ||
      ENV.fetch("SUPPORT_INBOUND_DOMAIN", "support.example.com")
  end

  # From address for the transactional/auth stream (magic-links) — deliberately
  # distinct from the support desk's support@ From so auth mail is unreplyable
  # and can carry its own reputation. Set via credentials[:ses][:transactional_from].
  def self.transactional_from
    Rails.application.credentials.dig(:ses, :transactional_from) ||
      "noreply@#{inbound_domain}"
  end
end
