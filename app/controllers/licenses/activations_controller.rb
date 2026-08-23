# The live activations panel on a mirrored license's page: asks Lemon Squeezy
# which machines the key is currently activated on. Rendered into a lazy turbo
# frame, so a slow or failing LS call degrades to a note in the panel rather
# than a broken license page. Admin only, like the rest of the desk.
class Licenses::ActivationsController < ApplicationController
  include LicenseScoped
  before_action -> { authorize! License, to: :manage }

  def show
    @instances = @license.external? ? License::LemonSqueezy.instances(@license.external_id) : []
  rescue => e
    @error = e.message
  end
end
