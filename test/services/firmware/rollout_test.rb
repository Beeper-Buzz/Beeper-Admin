require 'test_helper'

class Firmware::RolloutTest < ActiveSupport::TestCase
  Bundle = Struct.new(:version, :rollout_percent)

  def device(i)
    Digest::SHA256.hexdigest("device-#{i}")
  end

  test 'the bucket is SHA-256(device:version), first 8 bytes big-endian, mod 100' do
    expected = Digest::SHA256.digest("#{DEVICE}:1.4.0")[0, 8].unpack1('Q>') % 100
    assert_equal expected, Firmware::Rollout.bucket(DEVICE, '1.4.0')
    assert_equal Firmware::Rollout.bucket(DEVICE, '1.4.0'), Firmware::Rollout.bucket(DEVICE, '1.4.0')
  end

  test 'raising the percentage only adds devices' do
    1000.times do |i|
      in10 = Firmware::Rollout.eligible?(Bundle.new('1.4.0', 10), device(i))
      in50 = Firmware::Rollout.eligible?(Bundle.new('1.4.0', 50), device(i))
      assert in50, 'a device in at 10 % stays in at 50 %' if in10
    end
  end

  test 'about the right share of devices is in' do
    share = (0...10_000).count { |i| Firmware::Rollout.eligible?(Bundle.new('1.4.0', 25), device(i)) } / 10_000.0
    assert_in_delta 0.25, share, 0.03
  end

  test 'each version reshuffles devices' do
    first = (0...200).select { |i| Firmware::Rollout.eligible?(Bundle.new('1.4.0', 10), device(i)) }
    second = (0...200).select { |i| Firmware::Rollout.eligible?(Bundle.new('1.5.0', 10), device(i)) }
    refute_equal first, second
  end

  test '0 % is nobody, 100 % is everybody, no device hash only at 100 %' do
    refute Firmware::Rollout.eligible?(Bundle.new('1.4.0', 0), device(1))
    assert Firmware::Rollout.eligible?(Bundle.new('1.4.0', 100), device(1))
    assert Firmware::Rollout.eligible?(Bundle.new('1.4.0', 100), nil)
    refute Firmware::Rollout.eligible?(Bundle.new('1.4.0', 99), nil)
  end
end
