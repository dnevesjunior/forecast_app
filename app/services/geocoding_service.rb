class GeocodingService
  Location = Data.define(:zip, :latitude, :longitude, :display_name) do
    # as a fallback, I've decided to use lat / long with two decimals rounding (gives 1 km precision and similar forecast)
    def cache_key = zip.presence || format("%.2f,%.2f", latitude, longitude)
  end
  Error = Class.new(StandardError)
  NotFound = Class.new(Error)
  CACHE_TTL = 24.hours

  def self.call(address)
    new(address).call
  end

  def initialize(address)
    @address = address.to_s.strip
  end

  def call
    # check cache before calling Geocoder to avoid IP blacklisting under concurrent traffic
    Rails.cache.fetch("geocode/#{normalized_address}", expires_in: CACHE_TTL) { lookup }
  end

  private

  def normalized_address
    @address.downcase.squish
  end

  def lookup
    result = Geocoder.search(@address).first
    raise NotFound, "Address not found" if result.nil?

    Location.new(result.postal_code.presence, result.latitude, result.longitude, result.address)
  rescue Timeout::Error, SocketError => e
    raise Error, "Geocoding unavailable: #{e.message}"
  end
end
