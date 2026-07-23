module DownloadsHelper
  # A 2-letter ISO country code as its flag emoji ("US" -> 🇺🇸) by mapping each
  # letter to its Regional Indicator Symbol. Falls back to a neutral flag.
  def country_flag(code)
    return "🏳️" unless code.to_s.match?(/\A[A-Za-z]{2}\z/)
    code.upcase.each_char.map { |ch| (ch.ord - "A".ord + 0x1F1E6) }.pack("U*")
  end

  # "🇺🇸 US · California", or just "🇺🇸 US" when the region is unknown.
  def download_location(geo)
    label = "#{country_flag(geo.country)} #{geo.country}"
    geo.region.present? ? "#{label} · #{geo.region}" : label
  end
end
