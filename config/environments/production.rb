require "active_support/core_ext/integer/time"

Rails.application.configure do
  # ---- Email: Amazon SES ----
  # Send (:ses_v2) + receive (Action Mailbox :ses ingress). Both stay dormant
  # until the matching credentials are present, so a keyless prod boots clean and
  # dev keeps using letter_opener. See docs/ses-migration-runbook.md.

  # Outbound: SES v2 (aws-actionmailer-ses). Activated by the :ses credentials.
  if (ses = Rails.application.credentials.ses)
    config.action_mailer.delivery_method = :ses_v2
    config.action_mailer.ses_v2_settings = {
      region: ses[:region] || "us-east-1",
      credentials: Aws::Credentials.new(ses[:access_key_id], ses[:secret_access_key])
    }.tap do |s|
      # Transactional stream: no open/click tracking (see runbook Step 6). The
      # marketing stream, when it lands, overrides this per-mailer via
      # `default delivery_method_options: { configuration_set_name: ... }`.
      cs = ses[:transactional_config_set]
      s[:configuration_set_name] = cs if cs.present?
    end
  end

  # Inbound: SES receipt rule → S3 → SNS → the :ses ingress. Activated by the
  # support SNS topic ARN. Routes to TicketsMailbox (see ADR 0010).
  if (topic = Rails.application.credentials.dig(:support, :sns_topic_arn)).present?
    config.action_mailbox.ingress = :ses
    config.action_mailbox.ses.subscribed_topics = [ topic ]
  end

  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy
  # (kamal-proxy). Lets Rails treat forwarded requests as HTTPS — correct https URLs
  # in mailers (magic-links) and secure cookies.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint so Kamal's
  # healthcheck to /up never gets a 301.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Host for URLs in mailer templates (magic-link sign-in, etc.). The app's web
  # host — independent of the SES sending identity. From credentials[:ses][:host],
  # then APP_HOST, then a sane default.
  config.action_mailer.default_url_options = {
    host: Rails.application.credentials.dig(:ses, :host) || ENV.fetch("APP_HOST", "verkilo.com")
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
