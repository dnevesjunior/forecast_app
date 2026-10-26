require "rails_helper"

RSpec.describe GeocodingService do
  after { Geocoder::Lookup::Test.reset }

  describe ".call" do
    it "returns a Location with zip and coordinates" do
      Geocoder::Lookup::Test.add_stub(
        "1 Infinite Loop, Cupertino, CA",
        [{ "coordinates" => [37.3318, -122.0312],
           "postal_code" => "95014",
           "address"     => "1 Infinite Loop, Cupertino, CA 95014, USA" }]
      )

      location = described_class.call("1 Infinite Loop, Cupertino, CA")

      expect(location.zip).to eq("95014")
      expect(location.latitude).to eq(37.3318)
      expect(location.longitude).to eq(-122.0312)
    end

    it "strips whitespace before looking up" do
      Geocoder::Lookup::Test.add_stub("Cupertino, CA", [{ "coordinates" => [1, 2], "postal_code" => "95014" }])

      expect(described_class.call("  Cupertino, CA  ").zip).to eq("95014")
    end

    it "raises NotFound when nothing comes back" do
      Geocoder::Lookup::Test.add_stub("nowhere at all", [])

      expect { described_class.call("nowhere at all") }
        .to raise_error(GeocodingService::NotFound)
    end

    it "raises MissingZip when the result has no postal code" do
      Geocoder::Lookup::Test.add_stub("Paris", [{ "coordinates" => [48.85, 2.35], "postal_code" => nil }])

      expect { described_class.call("Paris") }
        .to raise_error(GeocodingService::MissingZip)
    end

    it "raises Error when the provider times out" do
      allow(Geocoder).to receive(:search).and_raise(Timeout::Error)

      expect { described_class.call("anything") }
        .to raise_error(GeocodingService::Error, /unavailable/)
    end
  end
end