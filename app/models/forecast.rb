class Forecast < Data.define(:current_temp, :high, :low, :daily, :fetched_at)
  Day = Data.define(:date, :high, :low)
end
