require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Covenant
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Permit <details>/<summary> in Action Text so inbound support replies can
    # fold their quoted history into a collapsed disclosure (TicketsMailbox).
    # Ordered after Lexxy's own allowed_tags hook (same :action_text_content
    # load) so it appends to Lexxy's list rather than racing it.
    initializer "covenant.action_text_details", after: "lexxy.sanitization" do
      ActiveSupport.on_load(:action_text_content) do
        tags = ActionText::ContentHelper.allowed_tags
        if tags && !tags.include?("details")
          ActionText::ContentHelper.allowed_tags = tags + %w[ details summary ]
        end
      end
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Magic-link registration policy:
    #   :invite_only — only existing users may sign in; new accounts are added
    #                  out-of-band. (The first user ever is created via the Setup
    #                  flow, which runs only when no users exist — see SetupsController.)
    #   :open        — anyone may self-register via the Signup flow.
    config.x.authentication.registration_policy = :invite_only

    # ImageMagick is what's installed here; the Rails default (:vips) needs libvips.
    config.active_storage.variant_processor = :mini_magick
  end
end
