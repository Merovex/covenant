# The user editing themself: display name here, the picture via
# User::AvatarsController.
class User::SettingsController < ApplicationController
  def show
  end

  def update
    if Current.user.update(settings_params)
      redirect_to user_settings_path, notice: "Profile saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def settings_params
      params.expect(user: [ :name ])
    end
end
