class ForecastsController < ApplicationController
  def show
    @address = params[:address].to_s.strip
    return if @address.blank?

    @result = ForecastFetcher.call(@address)
  rescue GeocodingService::Error => e
    @error = e.message
    render status: :unprocessable_entity
  rescue WeatherClient::Error => e
    @error = e.message
    render status: :service_unavailable
  end
end
