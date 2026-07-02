class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :hotwire_native?, :current_theme, :current_tint

  # True when the request comes from the Hotwire Native wrapper (vs. web/PWA), so
  # views can suppress web nav chrome and let native nav take over. See
  # docs/decisions/0005-mobile-hotwire-native-pwa-dev.md.
  def hotwire_native?
    request.user_agent.to_s.match?(/Hotwire Native|Turbo Native/)
  end

  # Persisted appearance prefs (set as cookies by the theme/tint Stimulus
  # controllers). Whitelisted/sanitized so they're safe to render into the
  # <html> attributes; unknown values fall back to the defaults.
  ALLOWED_THEMES = %w[light dark auto].freeze

  def current_theme
    ALLOWED_THEMES.include?(cookies[:theme]) ? cookies[:theme] : "light"
  end

  def current_tint
    cookies[:tint].to_s.match?(/\A[a-z]+(-[a-z0-9]+)?\z/) ? cookies[:tint] : "zinc"
  end
end
