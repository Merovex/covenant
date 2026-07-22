# Licenses on the spine — plain CRUD scoped to the current version of live
# licenses. Immutable like every recordable: an edit is a new version
# (record.revise), a delete is a trash on the history. Admin only.
class LicensesController < ApplicationController
  include LicenseScoped
  skip_before_action :set_record, only: %i[index new create]
  before_action -> { authorize! License, to: :manage }

  def index
    @licenses = License.current.includes(:record, :customer).order(:product, :license_key)
  end

  def show
  end

  def new
    @license = License.new(customer_id: params[:customer_id])
  end

  def create
    @license = License.new(license_params.merge(event: :created))

    if @license.valid?
      Record.originate(@license)
      redirect_to license_path(@license.record), notice: "License created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Immutable: every change is a version, so an edit revises the record rather
  # than mutating the row in place.
  def update
    @license = @record.revise(event: :updated, **license_params.to_h.symbolize_keys)

    if @license.errors.none?
      redirect_to license_path(@record), notice: "License updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.trash
    redirect_to licenses_path, notice: "License moved to trash."
  end

  private
    def license_params
      params.expect(license: [ :customer_id, :license_key, :product, :seats,
        :issued_at, :expires_at, :status ])
    end
end
