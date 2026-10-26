class ForecastFetcher
  Result = Data.define(:location, :forecast, :from_cache)
  CACHE_TTL = 30.minutes

  def self.call(address)
    new(address).call
  end

  def initialize(address)
    @address = address
  end

  def call
    location = GeocodingService.call(@address)
    key = cache_key(location.zip)

    if (cached = Rails.cache.read(key))
      return Result.new(location:, forecast: cached, from_cache: true)
    end

    forecast = WeatherClient.call(latitude: location.latitude, longitude: location.longitude)
    Rails.cache.write(key, forecast, expires_in: CACHE_TTL)
    Result.new(location:, forecast:, from_cache: false)
  end

  private

  def cache_key(zip) = "forecast/#{zip}"
end
