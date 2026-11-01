class ForecastsController < ApplicationController
  MAX_ADDRESS_LENGTH = 200
  ADDRESS_FORMAT = /\A[\p{L}\p{N}\s,.'#\-\/]+\z/

  rescue_from GeocodingService::Error, with: :unresolvable_address
  rescue_from WeatherClient::Error,    with: :weather_unavailable

  def show
    @address = params[:address].to_s.strip
    return blank_address if @address.blank?
    return invalid_address unless valid_address?

    @result = ForecastFetcher.call(@address)

    respond_to do |format|
      format.html
      format.json { render json: ForecastSerializer.call(@result) }
    end
  end

  private

  def valid_address?
    @address.length <= MAX_ADDRESS_LENGTH && @address.match?(ADDRESS_FORMAT)
  end

  # added json handling. HTML will keep showing empty form.
  def blank_address
    respond_to do |format|
      format.html { render :show }
      format.json { render json: { error: "address is required" }, status: :bad_request }
    end
  end

  def invalid_address
    render_error("Address must be up to #{MAX_ADDRESS_LENGTH} characters using letters, numbers and basic punctuation.", :bad_request)
  end

  def unresolvable_address(error)
    render_error(error.message, :unprocessable_content)
  end

  def weather_unavailable(error)
    render_error(error.message, :service_unavailable)
  end

  def render_error(message, status)
    @error = message
    respond_to do |format|
      format.html { render :show, status: status }
      format.json { render json: { error: message }, status: status }
    end
  end
end
