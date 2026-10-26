class WeatherClient
  Error = Class.new(StandardError)
  BASE_URL = "https://api.open-meteo.com/v1/forecast"

  def self.call(latitude:, longitude:) = new(latitude, longitude).call

  def initialize(latitude, longitude)
    @latitude, @longitude = latitude, longitude
  end

  def call
    response = get(build_uri)
    raise Error, "Open-Meteo returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    build_forecast(JSON.parse(response.body))
  rescue JSON::ParserError => e
    raise Error, "Invalid response: #{e.message}"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    raise Error, "Weather service unavailable: #{e.message}"
  end

  private

  def build_uri
    URI("#{BASE_URL}?" + URI.encode_www_form(
      latitude: @latitude, longitude: @longitude,
      current: "temperature_2m",
      daily: "temperature_2m_max,temperature_2m_min",
      temperature_unit: "fahrenheit", timezone: "auto", forecast_days: 7
    ))
  end

  def get(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
      http.get(uri.request_uri)
    end
  end

  def build_forecast(data)
    current = data.fetch("current")
    daily   = data.fetch("daily")

    days = daily.fetch("time").each_with_index.map do |date, i|
        Forecast::Day.new(
        date: Date.parse(date),
        high: daily.fetch("temperature_2m_max")[i],
        low:  daily.fetch("temperature_2m_min")[i]
        )
    end

    Forecast.new(
        current_temp: current.fetch("temperature_2m"),
        high: days.first.high,
        low: days.first.low,
        daily: days,
        fetched_at: Time.current
    )
  rescue KeyError => e
    raise Error, "Unexpected response shape: missing #{e.key}"
  end
end
