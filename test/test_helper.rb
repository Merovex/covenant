ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActionDispatch
  class IntegrationTest
    # Sign in by minting and redeeming a magic-link code (the real flow).
    def sign_in_as(user)
      get verify_session_path(code: user.sign_in_codes.create!.plaintext)
    end
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Run a block with `receiver.method` swapped for a stand-in (a value, or a
    # callable invoked with the original arguments). Minitest 6 dropped
    # minitest/mock; this is the slice of it we use — for keeping external
    # services (Lemon Squeezy) out of tests.
    def stubbing(receiver, method, stand_in)
      original = receiver.method(method)
      receiver.define_singleton_method(method) do |*args, **kwargs, &block|
        stand_in.respond_to?(:call) ? stand_in.call(*args, **kwargs, &block) : stand_in
      end
      yield
    ensure
      receiver.singleton_class.remove_method(method)
      receiver.define_singleton_method(method, original) if original.owner == receiver.singleton_class
    end

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
