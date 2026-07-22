# First-run install setup. Reachable only while no users exist; the first person
# to arrive creates the owner account (domain admin) and is emailed a magic link.
class SetupsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access
  before_action :require_no_users

  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_setup_path, alert: "Too many attempts. Try again later." }

  def new
    @setup = Setup.new
  end

  def create
    @setup = Setup.new(setup_params)
    if @setup.save
      expose_dev_sign_in_code(@setup.sign_in_code)
      redirect_to new_session_path(sent: true)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # The seeded system account isn't a real user, so it doesn't close the setup
  # window — only a signed-in-capable person does.
  def require_no_users
    redirect_to root_path if User.people.exists?
  end

  def setup_params
    params.expect(setup: :email_address)
  end
end
