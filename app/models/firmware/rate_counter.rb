# One row per rate-limited key; see Firmware::RateLimit. Compact nesting so the Firmware module
# comes from app/services/firmware.rb.
class Firmware::RateCounter < ApplicationRecord
  self.table_name = 'firmware_rate_counters'
end
