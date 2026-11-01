class ForecastSerializer
  def self.call(result)
    new(result).call
  end

  def initialize(result)
    @location = result.location
    @forecast = result.forecast
    @from_cache = result.from_cache
  end

  def call
    {
      location: {
        name: @location.display_name,
        zip: @location.zip,
        latitude: @location.latitude,
        longitude: @location.longitude
      },
      forecast: {
        current_temp: @forecast.current_temp,
        high: @forecast.high,
        low: @forecast.low,
        fetched_at: @forecast.fetched_at.iso8601,
        daily: @forecast.daily.map { |day| { date: day.date.iso8601, high: day.high, low: day.low } }
      },
      cache: @from_cache ? "hit" : "miss"
    }
  end
end
