# Discovery Sprint — forecast_app

Goal: be able to explain and defend every piece of this repo cold, as if a reviewer opened a random file and asked "why this?". Each item has what to know, questions a reviewer could ask, and a short hands-on exercise. Tick the box only when you can answer the questions without looking.

---

## 1. Rails skeleton & configuration

**Know**
- What each `rails new --skip-*` flag removed and what you'd need to add back to re-enable it
- Zeitwerk: file path ↔ constant name rules; `app/*` autoloaded, `lib/` not by default (`config.autoload_lib`)
- `config/initializers/*.rb`: loaded once at boot, alphabetical, after frameworks
- Environment files: what differs between `development.rb`, `test.rb`, `production.rb` (cache store, eager load, error pages)
- Credentials vs ENV: `credentials.yml.enc` + `master.key`, per-environment credentials, why a reviewer without `master.key` gets `nil`

**Reviewer questions**
- Why no Active Record? What would change if you added persistence later?
- Why does `ForecastFetcher` live in `app/services` and not `lib/`?
- What happens to `Rails.cache` in test by default, and why did you change it?

**Exercise (15 min)**
- Run `bin/rails zeitwerk:check`. Rename `forecast_fetcher.rb` to `fetcher.rb`, run it again, read the error, rename back.

- [ ] Done

---

## 2. The `geocoder` gem

**Know**
- What a "lookup" is; how `Geocoder.configure(lookup:)` swaps providers (Nominatim, Google, Mapbox) with the same `Geocoder.search` call
- Nominatim usage policy: identifying User-Agent, ~1 req/s, HTTPS; what "Access blocked" looks like
- `always_raise: :all` vs the default of swallowing errors into `[]`
- The gem's own cache (`cache:` option) and why it's off here
- `Geocoder::Lookup::Test`: `add_stub`, `set_default_stub`, `reset`; result hash keys (`coordinates`, `postal_code`, `address`)
- What a `Geocoder::Result` exposes: `latitude`, `longitude`, `postal_code`, `address`, `city`, `country_code`

**Reviewer questions**
- Why a gem instead of calling Nominatim directly?
- How would you move to Google Geocoding? What else would change (keys, quotas, result fields)?
- What does the gem do on a timeout with default config?

**Exercise (15 min)**
- In `rails c`, search three addresses: a full US street address, a city only, a non-US address. Inspect which have `postal_code`. Note which ones your service would reject and why.

- [ ] Done

---

## 3. `GeocodingService` — service objects & value objects

**Know**
- The `self.call` → `new(...).call` pattern: uniform interface, instance state, single stub seam
- `Data.define` vs `Struct` vs plain class: immutability, keyword init, `with`, equality by value, `to_h`
- Custom error hierarchy: `Error` base, `NotFound` and `MissingZip` subclasses; why callers rescue the base
- `rescue` on specific exceptions (`Timeout::Error`, `SocketError`) and re-raising as your own type

**Reviewer questions**
- Why raise instead of returning `nil` or a result object with `success?`?
- What's the contract of this class in one sentence?
- Why strip the input here rather than in the controller?

**Exercise (10 min)**
- Write, without looking, the `Location` definition and the three error classes. Compare with the file.

- [ ] Done

---

## 4. `WeatherClient` — HTTP from Ruby

**Know**
- `Net::HTTP.start(host, port, use_ssl:, open_timeout:, read_timeout:)`; difference between open and read timeout
- `URI.encode_www_form` and why you don't build query strings by hand
- `Net::HTTPSuccess` and the response class hierarchy; `response.code` vs `is_a?`
- `JSON.parse` failure modes; `Hash#fetch` + `KeyError` as a shape check
- Open-Meteo request params used (`current`, `daily`, `temperature_unit`, `timezone=auto`, `forecast_days`) and the response shape (parallel arrays in `daily`)
- Why stdlib over Faraday/HTTParty for one endpoint; when you *would* reach for Faraday (middleware, retries, instrumentation)

**Reviewer questions**
- What happens if Open-Meteo is slow? Where does the request give up?
- How would you add retries? A circuit breaker?
- Why is the unit hardcoded to Fahrenheit and where would a Celsius toggle live?

**Exercise (20 min)**
- Change the request to `temperature_unit=celsius` in `rails c` via a one-off `Net::HTTP` call and confirm the payload's `current_units` changes. Revert.

- [ ] Done

---

## 5. `Forecast` / `Forecast::Day` — modelling without a database

**Know**
- `class Forecast < Data.define(...)` vs `Data.define(...) do ... end` and the constant-scoping gotcha you hit
- Why value objects are safe to put in a cache: immutable, `Marshal`-able, equal by value
- Where domain objects live when they aren't AR models (`app/models` is fine; Rails doesn't care)

**Reviewer questions**
- How is this different from an AR model? What do you lose, what do you gain?
- If you needed to add `unit` or `timezone`, what breaks?

**Exercise (10 min)**
- In `rails c`: build a `Forecast`, call `.with(current_temp: 0)`, `.to_h`, `==` against a copy. Try to mutate it.

- [ ] Done

---

## 6. `ForecastFetcher` — orchestration & `Rails.cache`

**Know**
- `Rails.cache` API: `read`, `write(expires_in:)`, `fetch`, `exist?`, `delete`, `clear`
- Why `fetch` can't report hit/miss and the read-then-write alternative
- Stores: `:null_store`, `:memory_store` (per process, lost on restart), `:file_store`, `:mem_cache_store`, `:redis_cache_store`, Solid Cache (DB-backed); what Rails 8 generates by default and what `--skip-solid` left you with in production
- Cache key design: `forecast/<zip>`, namespace, why zip and not the raw address; what a normalized-address key would look like for geocoding
- Thundering herd / dog-pile on expiry and `race_condition_ttl`
- Why failures are never cached

**Reviewer questions**
- Two Puma workers, one request each for the same zip within 30 min: how many Open-Meteo calls with memory store? With Redis?
- Why geocode on every request even on a cache hit?
- What's the worst case if Nominatim goes down? If Open-Meteo goes down?

**Exercise (20 min)**
- Start `bin/rails s`, submit an address twice, watch the log for the Open-Meteo call appearing once. Restart the server, submit again, confirm it's fresh (memory store lost). Write one sentence on what Redis would change.

- [ ] Done

---

## 7. Controller & view

**Know**
- Thin controller: map outcomes to HTTP, nothing else; `rescue` in an action vs `rescue_from`
- Status codes chosen: 200, 422 (`:unprocessable_content`), 503; why not 404 for a bad address, why not 500
- `form_with url:, method: :get`: GET for idempotent lookups, shareable URL, no CSRF token needed
- `params[:address].to_s.strip`, `required` on the input, and what server-side validation exists vs doesn't
- `time_ago_in_words`, `strftime`, ERB escaping (`display_name` from a third party is rendered escaped by default)

**Reviewer questions**
- Where's input validation? What stops a 10 kB address?
- Why GET and not POST?
- How would you add Turbo so only the result block refreshes?

**Exercise (10 min)**
- Submit `<script>alert(1)</script>` as the address. Confirm it renders escaped in the error message / input value.

- [ ] Done

---

## 8. Test suite

**Know**
- Unit vs request specs: what each layer stubs and why (fixtures for the clients, `allow(...).to receive(:call)` for the orchestrator, both for requests)
- WebMock: `disable_net_connect!`, `stub_request(...).with(query: hash_including(...))`, `.to_return`, `.to_timeout`; what the "Real HTTP connections are disabled" error means
- `rspec-mocks`: `allow` vs `expect`, `have_received(...).once/.twice`, `and_raise`, partial doubles on classes
- `file_fixture` and `config.file_fixture_path`
- `ActiveSupport::Testing::TimeHelpers`: `travel`, `travel_to`, `freeze_time`; why `travel 31.minutes` expires the memory store
- `Rails.cache.clear` before each example and why order-dependent tests are a smell
- The mutation check habit: break one line, confirm red, restore

**Reviewer questions**
- Why stub `GeocodingService` and `WeatherClient` in the fetcher spec instead of using fixtures again?
- What would a Capybara system spec add that the request spec doesn't?
- How do you know the specs would catch a change in Open-Meteo's response shape?

**Exercise (15 min)**
- Delete `WebMock.disable_net_connect!`, run the suite, observe nothing fails. Explain why that's dangerous. Put it back.

- [ ] Done

---

## 9. Tooling, CI, repo hygiene

**Know**
- `rubocop-rails-omakase`: what it enforces (space inside array brackets, double quotes, trailing newline) and why you follow it instead of overriding
- Brakeman: what it scans for; why a no-DB app still gets value (XSS, open redirect, mass assignment)
- The generated GitHub Actions workflow: jobs, `ruby/setup-ruby` and the `.ruby-version` ↔ runner image constraint you hit
- `.ruby-version` + `Gemfile` `ruby file:` directive; `Gemfile.lock` records the Ruby version
- Branch per PR, commit messages that mirror the blueprint, `git grep -i apple` before push

**Reviewer questions**
- Walk me through what CI runs and what would fail if I removed a spec.
- Why Ruby 3.3.13 and not 3.4?

**Exercise (10 min)**
- Read `.github/workflows/ci.yml` top to bottom and say what each step does in one line.

- [ ] Done

---

## 10. Interview-ready answers (write each in 3–5 sentences, then say it out loud)

- [ ] "Walk me through a request from form submit to rendered page."
- [ ] "Why these two external APIs?"
- [ ] "Explain your caching strategy and its limits."
- [ ] "What did you deliberately not build, and why?"
- [ ] "What would you change for production traffic?"
- [ ] "Where would this break first under load or failure?"

---

## Sprint plan

| Day | Blocks |
|-----|--------|
| 1 | §1, §2, §3 |
| 2 | §4, §5, §6 |
| 3 | §7, §8 |
| 4 | §9, §10 — then record yourself answering §10 and listen back |

Rule: no block is "done" from reading alone. Each has an exercise; do it.
