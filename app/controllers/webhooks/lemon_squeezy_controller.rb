# Inbound Lemon Squeezy webhooks. No session, no CSRF: the request is
# authenticated by its X-Signature (HMAC-SHA256 of the raw body with the
# signing secret we entered when registering the webhook in LS). License-key
# and order events go straight through the same upserts the daily sync uses;
# everything else is acknowledged and ignored, so LS doesn't retry it.
class Webhooks::LemonSqueezyController < ActionController::API
  LICENSE_EVENTS = %w[ license_key_created license_key_updated ].freeze
  ORDER_EVENTS = %w[ order_created order_refunded ].freeze

  before_action :verify_signature

  def create
    payload = JSON.parse(request.raw_post)
    event = payload.dig("meta", "event_name")

    case event
    when *LICENSE_EVENTS then License::LemonSqueezy.upsert(payload.fetch("data"))
    when *ORDER_EVENTS   then License::LemonSqueezy.upsert_order(payload.fetch("data"))
    end
    head :ok
  rescue JSON::ParserError, KeyError
    head :bad_request
  end

  private
    # Unconfigured → 404: a webhook nobody registered is a page that doesn't
    # exist. Bad or missing signature → 401 (LS shows it in the webhook log).
    def verify_signature
      secret = License::LemonSqueezy.webhook_secret
      return head :not_found if secret.blank?

      digest = OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)
      signature = request.headers["X-Signature"].to_s
      head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(digest, signature)
    end
end
