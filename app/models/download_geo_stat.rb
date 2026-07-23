# Downloads by location (country + region/state), mirrored from the Cloudflare
# downloads Worker. Cloudflare resolves the geography from the IP at the edge, so
# we only ever store the resolved country/region, never an IP. This is a rolling
# snapshot over the Worker's window (~90 days), replaced on each sync — unlike
# DownloadStat's daily series, it isn't kept as long-term history.
class DownloadGeoStat < ApplicationRecord
  validates :country, presence: true

  scope :busiest, -> { order(count: :desc, country: :asc, region: :asc) }
end
