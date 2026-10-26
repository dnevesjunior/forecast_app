require "rails_helper"

RSpec.describe "Forecasts", type: :request do
  let(:location) { GeocodingService::Location.new(zip: "95014", latitude: 37.33, longitude: -122.03, display_name: "Cupertino, CA") }
  let(:forecast) do
    Forecast.new(current_temp: 57.3, high: 73.5, low: 47.2,
                 daily: [ Forecast::Day.new(date: Date.new(2026, 10, 25), high: 73.5, low: 47.2) ],
                 fetched_at: Time.current)
  end

  before do
    allow(GeocodingService).to receive(:call).and_return(location)
    allow(WeatherClient).to receive(:call).and_return(forecast)
  end

  it "renders the form with no address" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="address"')
    expect(WeatherClient).not_to have_received(:call)
  end

  it "shows current temperature, high and low" do
    get root_path, params: { address: "1 Infinite Loop" }
    expect(response.body).to include("57.3", "73.5", "47.2", "Cupertino, CA")
    expect(response.body).not_to include("From cache")
  end

  it "shows the cache indicator on a repeat request" do
    get root_path, params: { address: "1 Infinite Loop" }
    get root_path, params: { address: "1 Infinite Loop" }
    expect(response.body).to include("From cache")
  end

  it "returns 422 with a message when the address is not found" do
    allow(GeocodingService).to receive(:call).and_raise(GeocodingService::NotFound, "Address not found")
    get root_path, params: { address: "???" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Address not found")
  end

  it "returns 503 with a message when the weather service is down" do
    allow(WeatherClient).to receive(:call).and_raise(WeatherClient::Error, "Weather service unavailable")
    get root_path, params: { address: "1 Infinite Loop" }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include("Weather service unavailable")
  end
end