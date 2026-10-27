class ForecastsController < ApplicationController
  rescue_from GeocodingService::Error, with: :unresolvable_address
  rescue_from WeatherClient::Error,    with: :weather_unavailable

  def show
    @address = params[:address].to_s.strip
    return if @address.blank?

    @result = ForecastFetcher.call(@address)
  end

  private

  def unresolvable_address(error)
    @error = error.message
    render :show, status: :unprocessable_content
  end

  def weather_unavailable(error)
    @error = error.message
    render :show, status: :service_unavailable
  end
end
