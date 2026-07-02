# Registration policy for users, driven by
# config.x.authentication.registration_policy (:invite_only or :open). The
# first-user bootstrap is NOT here — that's the Setup flow (SetupsController),
# which only runs when no users exist.
module User::Registration
  extend ActiveSupport::Concern

  class_methods do
    # Which policy is in effect (:invite_only or :open).
    def registration_policy
      Rails.configuration.x.authentication.registration_policy
    end

    # True when anyone may self-register (via the Signup flow).
    def registration_open?
      registration_policy == :open
    end

    # Existing user for an address, normalizing it the same way we store it.
    def with_email_address(email_address)
      find_by(email_address: normalize_value_for(:email_address, email_address))
    end
  end
end
