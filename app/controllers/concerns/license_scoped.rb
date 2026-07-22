# Resolves the Record (the public identity — /licenses/:id is a Record id,
# never a version id) and its current version for license-facing controllers.
module LicenseScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Record.active.licenses.find(params[:id])
      @license = @record.recordable
    end
end
