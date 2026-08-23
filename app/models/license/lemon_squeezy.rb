require "net/http"

# Mirrors Lemon Squeezy license keys into License (ADR 0011). Two entry points
# feed one upsert: SyncLemonSqueezyLicensesJob pages through the store's keys
# (hourly + the "Sync" button), and Webhooks::LemonSqueezyController hands in
# the key from a license_key_created/updated event. Either way a new key
# originates a License; a changed key revises it with a "synced" version, so
# renewals, disables and new activations land in the spine's history.
#
# Secrets: the API key (and optional store id / webhook signing secret) come
# from ENV first, credentials second — the same ladder as DownloadStat::Worker.
module License::LemonSqueezy
  module_function

  API = "https://api.lemonsqueezy.com/v1".freeze
  PAGE_SIZE = 100
  LAST_SYNCED_KEY = "lemon_squeezy/last_synced_at".freeze

  # LS key status → our License status. "inactive" just means not yet
  # activated on any machine; the customer still holds a live license.
  STATUS = { "inactive" => "active", "active" => "active", "expired" => "expired", "disabled" => "revoked" }.freeze

  def api_key
    ENV["LEMON_SQUEEZY_API_KEY"].presence || Rails.application.credentials.lemon_squeezy_api_key
  end

  # Optional: restrict the pull to one store when the API key sees several.
  def store_id
    ENV["LEMON_SQUEEZY_STORE_ID"].presence || Rails.application.credentials.lemon_squeezy_store_id
  end

  # Shared secret entered when registering the webhook in LS (X-Signature).
  def webhook_secret
    ENV["LEMON_SQUEEZY_WEBHOOK_SECRET"].presence || Rails.application.credentials.lemon_squeezy_webhook_secret
  end

  def configured? = api_key.present?

  def last_synced_at
    Rails.cache.read(LAST_SYNCED_KEY)
  end

  # Pull every key from LS and mirror it. Idempotent. Returns a tally like
  # { created: 1, updated: 0, unchanged: 4, skipped: 0 }.
  def sync!(now: Time.current)
    products = product_names
    tally = Hash.new(0)
    each_license_key { |resource| tally[upsert(resource, products: products)] += 1 }
    Rails.cache.write(LAST_SYNCED_KEY, now)
    tally
  end

  # Mirror one LS license-key resource ({ "id" => …, "attributes" => { … } },
  # the shape both the API and webhooks use). Returns :created, :updated,
  # :unchanged, or :skipped (the mirrored license is in our trash — staff put
  # it there on purpose; restoring it resumes syncing).
  def upsert(resource, products: product_names)
    attrs = attributes_for(resource, products)
    license = mirrored_license(attrs[:external_id])

    if license.nil?
      Record.originate(License.new(attrs.merge(event: :created, creator: User.system)))
      :created
    elsif license.record.trashed?
      :skipped
    elsif changed?(license, attrs)
      revised = license.record.revise(event: :synced, creator: User.system, **attrs)
      raise ActiveRecord::RecordInvalid, revised if revised.errors.any?
      :updated
    else
      :unchanged
    end
  end

  # Live activations of a key, straight from LS (for the license page's
  # activations panel — not stored; this is the "which machines" question).
  # [{ "identifier" => …, "name" => …, "created_at" => … }, …]
  def instances(external_id)
    get("license-key-instances", "filter[license_key_id]" => external_id)["data"].to_a.map { |d| d["attributes"] }
  end

  # { product_id => name } for the store — LS keys carry only the product id.
  def product_names
    Rails.cache.fetch("lemon_squeezy/products", expires_in: 1.hour) do
      each_page("products").each_with_object({}) { |d, map| map[d["id"].to_s] = d.dig("attributes", "name") }
    end
  end

  # -- translation ---------------------------------------------------------

  def attributes_for(resource, products)
    a = resource.fetch("attributes")
    product_id = a["product_id"].to_s
    {
      external_id: resource.fetch("id").to_s,
      external_order_id: a["order_id"]&.to_s,
      customer_id: customer_for(a).id,
      license_key: a.fetch("key"),
      product: products[product_id].presence || "Product #{product_id}",
      status: a["disabled"] ? "revoked" : STATUS.fetch(a["status"], "active"),
      activation_limit: a["activation_limit"],
      instances_count: a["instances_count"].to_i,
      seats: a["activation_limit"] || 1,
      issued_at: parse_time(a["created_at"]),
      expires_at: parse_time(a["expires_at"])
    }
  end

  # The LS buyer becomes (or already is) a Customer, matched on email.
  def customer_for(attributes)
    email = attributes["user_email"].to_s.strip.downcase
    raise ArgumentError, "Lemon Squeezy license key #{attributes["key"]} has no user_email" if email.blank?

    Customer.find_or_create_by!(email: email) do |customer|
      customer.name = attributes["user_name"].presence || email
    end
  end

  # The current version of the License mirroring this LS key — trashed or
  # not (a trashed one must not be re-originated as a duplicate).
  def mirrored_license(external_id)
    License.where(id: Record.licenses.select(:recordable_id)).find_by(external_id: external_id)
  end

  # Would applying attrs change anything? Asked of a throwaway copy so AR's
  # casting (times, integers) does the comparing and the live row stays clean.
  def changed?(license, attrs)
    probe = license.dup
    probe.clear_changes_information
    probe.assign_attributes(attrs)
    probe.changed?
  end

  def parse_time(value)
    value.present? ? Time.zone.parse(value) : nil
  end

  # -- HTTP ----------------------------------------------------------------

  def each_license_key(&block)
    params = {}
    params["filter[store_id]"] = store_id if store_id.present?
    each_page("license-keys", params, &block)
  end

  # Walk a paginated JSON:API collection, yielding each resource. Without a
  # block, returns the resources as an array.
  def each_page(path, params = {})
    return enum_for(:each_page, path, params).to_a unless block_given?

    page = 1
    loop do
      body = get(path, params.merge("page[number]" => page, "page[size]" => PAGE_SIZE))
      body["data"].to_a.each { |resource| yield resource }
      last = body.dig("meta", "page", "lastPage").to_i
      break if page >= last
      page += 1
    end
  end

  def get(path, params = {})
    raise "Lemon Squeezy API key is not configured" unless configured?

    uri = URI("#{API}/#{path}")
    uri.query = URI.encode_www_form(params) if params.any?
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/vnd.api+json"
    request["Authorization"] = "Bearer #{api_key}"

    response = Net::HTTP.start(uri.hostname, uri.port,
      use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }

    unless response.is_a?(Net::HTTPSuccess)
      raise "Lemon Squeezy request failed: HTTP #{response.code} #{response.body.to_s.truncate(300)}"
    end
    JSON.parse(response.body)
  end
end
