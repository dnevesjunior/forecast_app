require "rails_helper"

RSpec.describe ForecastFetcher do
  let(:location) { GeocodingService::Location.new(zip: "95014", latitude: 37.33, longitude: -122.03, display_name: "Cupertino, CA") }
  let(:forecast) { Forecast.new(current_temp: 57.3, high: 73.5, low: 47.2, daily: [], fetched_at: Time.current) }

  before do
    allow(GeocodingService).to receive(:call).and_return(location)
    allow(WeatherClient).to receive(:call).and_return(forecast)
  end

  it "fetches from the weather service on first request" do
    result = described_class.call("1 Infinite Loop")

    expect(WeatherClient).to have_received(:call).with(latitude: 37.33, longitude: -122.03).once
    expect(result.forecast).to eq(forecast)
    expect(result.from_cache).to be(false)
  end

  it "serves from cache on a second request for the same zip" do
    described_class.call("1 Infinite Loop")
    result = described_class.call("1 Infinite Loop")

    expect(WeatherClient).to have_received(:call).once
    expect(result.from_cache).to be(true)
  end

  it "shares the cache across different addresses in the same zip" do
    described_class.call("1 Infinite Loop")
    result = described_class.call("10600 N Tantau Ave")

    expect(WeatherClient).to have_received(:call).once
    expect(result.from_cache).to be(true)
  end

  it "refetches after 30 minutes" do
    described_class.call("1 Infinite Loop")
    travel 31.minutes do
      result = described_class.call("1 Infinite Loop")
      expect(result.from_cache).to be(false)
    end
    expect(WeatherClient).to have_received(:call).twice
  end

  it "does not cache when the weather service fails" do
    allow(WeatherClient).to receive(:call).and_raise(WeatherClient::Error, "down")

    expect { described_class.call("1 Infinite Loop") }.to raise_error(WeatherClient::Error)
    expect(Rails.cache.exist?("forecast/95014")).to be(false)
  end

  it "propagates geocoding errors without touching the weather service" do
    allow(GeocodingService).to receive(:call).and_raise(GeocodingService::NotFound, "nope")

    expect { described_class.call("???") }.to raise_error(GeocodingService::NotFound)
    expect(WeatherClient).not_to have_received(:call)
  end
end
