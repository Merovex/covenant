ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Run a block with the magic-link registration policy temporarily overridden.
    def with_registration_policy(policy)
      config = Rails.configuration.x.authentication
      original = config.registration_policy
      config.registration_policy = policy
      yield
    ensure
      config.registration_policy = original
    end
  end
end
