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

  # Where the acknowledgement autoresponder points customers to screen-record a
  # bug. A single knob; swap for your recorder (Loom, etc.) via ENV/credentials.
  def self.support_video_url
    Rails.application.credentials.dig(:support, :video_url) ||
      ENV.fetch("SUPPORT_VIDEO_URL", "https://#{inbound_domain}/record")
  end
end
