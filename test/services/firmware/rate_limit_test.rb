require 'test_helper'
require 'minitest/mock'

class Firmware::RateLimitTest < ActiveSupport::TestCase
  teardown { Firmware.reset_config! }

  test 'pruning on a short-window rule keeps the live counters of a long-window rule' do
    now = Time.current
    device_key = "report_device:#{DEVICE}"
    Firmware::RateCounter.create!(key: device_key, window_started_at: now - 3.hours, hits: 100)
    Firmware::RateCounter.create!(key: 'check_ip:stale', window_started_at: now - 3.days, hits: 1)

    Firmware::RateLimit.stub(:rand, 0.0) do # always prune
      assert Firmware::RateLimit.allow_all?({ check_ip: 'some-ip' }, now: now)
    end

    assert_equal 100, Firmware::RateCounter.find_by(key: device_key)&.hits, 'the 24 h device counter survives'
    assert_nil Firmware::RateCounter.find_by(key: 'check_ip:stale'), 'rows past twice the longest window go'
    refute Firmware::RateLimit.allow_all?({ report_device: DEVICE }, now: now), 'the device is still over its limit'
  end
end
