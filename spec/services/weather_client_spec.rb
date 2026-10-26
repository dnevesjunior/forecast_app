require "rails_helper"

RSpec.describe WeatherClient do
  let(:lat) { 37.3318 }
  let(:lon) { -122.0312 }
  let(:body) { file_fixture("open_meteo/cupertino.json").read }

  def stub_open_meteo(status: 200, body: "")
    stub_request(:get, "https://api.open-meteo.com/v1/forecast")
      .with(query: hash_including("latitude" => lat.to_s, "longitude" => lon.to_s))
      .to_return(status:, body:, headers: { "Content-Type" => "application/json" })
  end

  describe ".call" do
    it "returns a Forecast with current temperature" do
      stub_open_meteo(body:)
      forecast = described_class.call(latitude: lat, longitude: lon)
      expect(forecast.current_temp).to eq(JSON.parse(body).dig("current", "temperature_2m"))
    end

    it "includes today's high and low" do
      stub_open_meteo(body:)
      forecast = described_class.call(latitude: lat, longitude: lon)
      expect(forecast.high).to be > forecast.low
    end

    it "includes a 7-day extended forecast" do
      stub_open_meteo(body:)
      forecast = described_class.call(latitude: lat, longitude: lon)
      expect(forecast.daily.size).to eq(7)
      expect(forecast.daily.first).to respond_to(:date, :high, :low)
    end

    it "raises Error on a non-200 response" do
      stub_open_meteo(status: 503, body: "upstream down")
      expect { described_class.call(latitude: lat, longitude: lon) }
        .to raise_error(WeatherClient::Error, /503/)
    end

    it "raises Error on a timeout" do
      stub_request(:get, /api.open-meteo.com/).to_timeout
      expect { described_class.call(latitude: lat, longitude: lon) }
        .to raise_error(WeatherClient::Error)
    end

    it "raises Error on malformed JSON" do
      stub_open_meteo(body: "not json")
      expect { described_class.call(latitude: lat, longitude: lon) }
        .to raise_error(WeatherClient::Error)
    end
  end
end