# FORECAST APP

A weather forecast webapp. It receives an address, contacts a Geocoding service for coordinates, fetches forecast from Open-Meteo and shows it as HTML or JSON. Rails 8, 30 minutes cache (by localization) and JSON API, with response pointing whether it came from cache or not.

Rails 8, Ruby 3.3.13, no database. Built as a take-home assessment.

---

## Running it

### With Docker (Redis included)

```bash
docker compose up --build
```

Then, open http://localhost:3000. `Dockerfile.dev` was used as the compose file with a `redis:7-alpine` container. Redis is used as its cache store via `REDIS_URL`.

### Locally

``` bash
bundle install
bin/rails server
```

If `REDIS_URL` is not available, the app falls back to an in-memory cache store. Set `REDIS_URL=redis://localhost:6379/1` to use a local Redis instead.

### JSON API

```bash
curl -s "http://localhost:3000/forecast.json?address=1+Infinite+Loop,+Cupertino" | jq           # "cache": "miss"
curl -s "http://localhost:3000/forecast.json?address=1+Infinite+Loop,+Cupertino" | jq .cache    # "hit"
curl -s -i "http://localhost:3000/forecast.json" | head -1                                       # HTTP/1.1 400 Bad Request
```

Response shape:

```json
{
  "location": { "name": "1 Infinite Loop, Cupertino, CA 95014, USA", "zip": "95014", "latitude": 37.33, "longitude": -122.03 },
  "forecast": {
    "current_temp": 57.3, "high": 73.5, "low": 47.2,
    "fetched_at": "2026-11-01T03:12:44Z",
    "daily": [ { "date": "2026-11-01", "high": 73.5, "low": 47.2 } ]
  },
  "cache": "miss"
}
```

Errors are received as `{ "error": "..." }`, using the same status code the HTML page uses.

### Seeing the cache

With the Docker setup running, you can run a few requests and check with the following commands:

```bash
docker compose exec redis redis-cli -n 1 keys '*'
docker compose exec redis redis-cli -n 1 ttl 'forecast/95014'
```

The TTL shows about 35 minutes, not 30. This is instentional and is explained on `race_condition_ttl` under design decisions.

### Tests

```bash
bundle exec rspec
```

---

## How a request flows

GET /?address=...   or   GET /forecast.json?address=...
  -> ForecastsController   validates length (<= 200) and characters -> 400 if invalid
  -> GeocodingService      Rails.cache "geocode/[normalized address]", 24h miss: Geocoder (Nominatim) -> Location (zip, lat, lon)
  -> ForecastFetcher       Rails.cache "forecast/[zip or rounded lat,lon]", 30min miss: WeatherClient (Open-Meteo) -> Forecast
  -> HTML view, or ForecastSerializer -> JSON with "cache": "hit" | "miss"
```

A repeated request for the same address inside 30 minutes makes no outbound HTTP calls. Both the geocoding result and the forecast come from the cache.

---

## Design Decisions

**Two cache layers with different TTLs.** Geocoding results are cached for 24 hours under the normalized address (downcased, whitespace squished), because an address always stays the same. Forecasts are cached for 30 minutes under the location key, because forecast does not always stays the same. Caching only the forecast would still send one Nominatim request per page load, and Nominatim allows 1 request per second, so that breaks under any real traffic.

**`race_condition_ttl` against cache stampedes.** When a forecast entry expires, every concurrent request would miss at once and all of them would call Open-Meteo. With `race_condition_ttl: 10.seconds`, the first request to see the expired entry extends it briefly and refreshes it; the others keep serving the stale value for those seconds instead of piling onto the upstream API. Rails stores the entry in Redis with an extra 5 minutes of TTL so the stale value is physically there to be served, which is why `redis-cli ttl` reports about 35 minutes.

**Location key: zip when available, rounded coordinates otherwise.** The original version raised when the geocoder returned no postal code, which rejected valid places all over the world. Now `Location#cache_key` returns the zip when there is one and otherwise latitude and longitude rounded to two decimals, which is roughly 1 km. Nearby points without a zip share a forecast, which is the behaviour you want from a weather cache.

**Input validation before any network call.** The controller checks the address length (200 characters) and allowed characters (Unicode letters and digits, spaces and the punctuation real addresses use) before calling any service. A malformed address never reaches the geocoder.

**One error type per service, mapped to HTTP status.** `GeocodingService::NotFound` and `GeocodingService::Error` become 422 (we tried and could not resolve the address); `WeatherClient::Error` becomes 503 (the upstream is down); invalid input is 400 (the client's fault, we did not try). The same mapping serves HTML and JSON.

**No database.** Nothing in this app needs to persist beyond the cache. Adding a database would mean migrations, a `db:prepare` step and a second service in Docker for no benefit. If the product needed history or user accounts, that would be the first thing to add.

**A separate serializer for the JSON contract.** `ForecastSerializer` builds the JSON payload from the internal `Result` object. The JSON shape is a public contract, while the internal objects are not, and I did not want a rename in one to silently change the other.

**Value objects.** `Location`, `Forecast` and `Result` are `Data.define` objects: immutable, compared by value and cheap to serialize into the cache.

---

## Trade-offs and what I would change for production

- **Nominatim is fine for a demo, not for production.** It has a hard 1 request/second limit and no SLA. The cache keeps us well under the limit for repeated addresses, but a burst of new addresses would still hit it. In production I would use a paid geocoding provider, or put geocoding behind a rate-limited queue.
- **The API has no authentication or rate limiting.** Anyone who can reach it can use it. A real deployment would need at least an API key and a per-client rate limit.
- **In-memory cache is per process.** Two Puma workers would each keep their own cache, so hit rates drop and the upstream limits get closer. That is why the Docker setup uses Redis; production would too.
- **`redis-cli keys '*'`** is only for looking around in development. On a large keyspace it blocks the server; `scan` is the production-safe equivalent.
- **No ETag or HTTP caching on the JSON endpoint.** `fetched_at` tells the client how old the data is, but a conditional request would save bandwidth.
- **Address normalization is simple.** "1 Infinite Loop" and "One Infinite Loop" are different cache keys. Canonicalizing through the geocoder's own output would merge them, at the cost of one geocoding call per variant.

---

## Testing

RSpec, with WebMock blocking all real network access and the Geocoder gem in `:test` mode with stubbed lookups. `Rails.cache` is cleared before every example.

The specs that matter most for this challenge:

- `spec/services/geocoding_service_spec.rb` is used to prove that repeated and different formats of the same address hit the geocoder once, that failed lookups are not cached, and that `Location#cache_key` falls back to rounded coordinates.
- `spec/services/forecast_fetcher_spec.rb` is used to prove the forecast cache, the `from_cache` flag and the coordinate-based key.
- `spec/requests/forecasts_spec.rb` is used to cover the HTML page, the JSON endpoint (miss, hit, 400, 422), input validation, and one end-to-end check that two requests for the same address call `Geocoder.search` and `WeatherClient` exactly once.

CI runs Brakeman, bundler-audit, importmap audit, RuboCop and the full RSpec suite against a real Redis service container, so the caching behaviour described here is tested on the same store the Docker setup uses.

---