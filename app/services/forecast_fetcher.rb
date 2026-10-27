class ForecastFetcher
  Result = Data.define(:location, :forecast, :from_cache)
  CACHE_TTL = 30.minutes
  RACE_TTL  = 10.seconds

  def self.call(address)
    new(address).call
  end

  def initialize(address)
    @address = address
  end

  def call
    location = GeocodingService.call(@address)
    from_cache = true

    # The block only runs on a cache miss, so from_cache ends up false exactly when we fetched.
    # race_condition_ttl lets one process refresh an expired entry while others briefly keep
    # serving the stale value, instead of all hitting Open-Meteo at the same moment.
    forecast = Rails.cache.fetch(cache_key(location.zip), expires_in: CACHE_TTL, race_condition_ttl: RACE_TTL) do
      from_cache = false
      WeatherClient.call(latitude: location.latitude, longitude: location.longitude)
    end

    Result.new(location:, forecast:, from_cache:)
  end

  private

  def cache_key(zip) = "forecast/#{zip}"
end
