class GeocodingService
    Location = Data.define(:zip, :latitude, :longitude, :display_name)
    Error = Class.new(StandardError)
    NotFound = Class.new(Error)
    MissingZip = Class.new(Error)

    def self.call(address) = new(address).call

    def initialize(address) = @address = address.to_s.strip

    def call
        result = Geocoder.search(@address).first
        raise NotFound, "Address not found" if result.nil?
        raise MissingZip, "No postal code for that address" if result.postal_code.blank?
        
        Location.new(result.postal_code, result.latitude, result.longitude, result.address)
    rescue Timeout::Error, SocketError => e
        raise Error, "Geocoding unavailable: #{e.message}"
    end
end
