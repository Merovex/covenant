# Licenses on the spine — plain CRUD scoped to the current version of live
# licenses. Immutable like every recordable: an edit is a new version
# (record.revise), a delete is a trash on the history. Admin only.
class LicensesController < ApplicationController
  include LicenseScoped
  skip_before_action :set_record, only: %i[index new create sync]
  before_action -> { authorize! License, to: :manage }
  # Mirrored licenses are edited in Lemon Squeezy; a local edit would just be
  # overwritten by the next sync.
  before_action :refuse_external_edit, only: %i[edit update]

  def index
    @licenses = License.current.includes(:record, :customer).order(:product, :license_key)
    @lemon_squeezy = License::LemonSqueezy.configured?
    @last_synced = License::LemonSqueezy.last_synced_at
  end

  # Manual "Sync" — mirror Lemon Squeezy right now (admin action, so blocking
  # briefly is fine), then show the fresh list. The hourly job and the webhook
  # do the same without anyone asking.
  def sync
    tally = License::LemonSqueezy.sync!
    redirect_to licenses_path, notice: "Synced from Lemon Squeezy: #{tally.map { |k, v| "#{v} #{k}" }.join(", ")}."
  rescue => e
    redirect_to licenses_path, alert: "Couldn't sync from Lemon Squeezy: #{e.message}"
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
    def refuse_external_edit
      return unless @license.external?

      redirect_to license_path(@record), alert: "This license is mirrored from Lemon Squeezy — edit it there; changes sync back automatically."
    end

    def license_params
      params.expect(license: [ :customer_id, :license_key, :product, :seats,
        :issued_at, :expires_at, :status ])
    end
end
