require "rails_helper"

RSpec.describe GeocodingService do
  after { Geocoder::Lookup::Test.reset }

  let(:cupertino) do
    [ { "coordinates" => [ 37.3318, -122.0312 ], "postal_code" => "96014", "address" => "1 Infinite Loop, Cupertino, CA 95014, USA" } ]
  end

  describe ".call" do
    it "returns a Location with zip and coordinates" do
      Geocoder::Lookup::Test.add_stub(
        "1 Infinite Loop, Cupertino, CA",
        [ { "coordinates" => [ 37.3318, -122.0312 ],
           "postal_code" => "95014",
           "address"     => "1 Infinite Loop, Cupertino, CA 95014, USA" } ]
      )

      location = described_class.call("1 Infinite Loop, Cupertino, CA")

      expect(location.zip).to eq("95014")
      expect(location.latitude).to eq(37.3318)
      expect(location.longitude).to eq(-122.0312)
    end

    it "strips whitespace before looking up" do
      Geocoder::Lookup::Test.add_stub("Cupertino, CA", [ { "coordinates" => [ 1, 2 ], "postal_code" => "95014" } ])

      expect(described_class.call("  Cupertino, CA  ").zip).to eq("95014")
    end

    it "raises NotFound when nothing comes back" do
      Geocoder::Lookup::Test.add_stub("nowhere at all", [])

      expect { described_class.call("nowhere at all") }
        .to raise_error(GeocodingService::NotFound)
    end

    it "raises Error when the provider times out" do
      allow(Geocoder).to receive(:search).and_raise(Timeout::Error)

      expect { described_class.call("anything") }
        .to raise_error(GeocodingService::Error, /unavailable/)
    end

    it "returns a Location with nil zip when the result has no postal code" do
      Geocoder::Lookup::Test.add_stub("Paris", [ { "coordinates" => [ 48.85, 2.35 ], "postal_code" => "" } ])

      location = described_class.call("Paris")

      expect(location.zip).to be_nil
      expect(location.latitude).to eq(48.85)
    end
  end

    describe "caching" do
    before { Geocoder::Lookup::Test.add_stub("Cupertino, CA", cupertino) }

    it "only hits the geocoder once for the same address" do
      allow(Geocoder).to receive(:search).and_call_original

      described_class.call("Cupertino, CA")
      described_class.call("Cupertino, CA")

      expect(Geocoder).to have_received(:search).once
    end

    it "treats case and extra whitespace as the same address" do
      allow(Geocoder).to receive(:search).and_call_original

      described_class.call("Cupertino, CA")
      described_class.call("  cupertino,    ca ")

      expect(Geocoder).to have_received(:search).once
    end

    it "does not cache a failed lookup" do
      Geocoder::Lookup::Test.add_stub("nowhere at all", [])

      expect { described_class.call("nowhere at all") }.to raise_error(GeocodingService::NotFound)
      expect(Rails.cache.exist?("geocode/nowhere at all")).to be(false)
    end
  end

    describe GeocodingService::Location do
    it "uses the zip as cache key when present" do
      location = described_class.new(zip: "95014", latitude: 37.33, longitude: -122.03, display_name: "x")
      expect(location.cache_key).to eq("95014")
    end

    it "falls back to coordinates rounded to two decimals" do
      location = described_class.new(zip: nil, latitude: 48.8566, longitude: 2.3522, display_name: "Paris")
      expect(location.cache_key).to eq("48.86,2.35")
    end
  end
end
