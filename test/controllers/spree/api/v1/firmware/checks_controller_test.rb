require 'test_helper'

# GET /api/v1/firmware/check: bundle choice, rollout, channels, gates, kill switch, install order.
class Spree::Api::V1::Firmware::ChecksControllerTest < ActionDispatch::IntegrationTest
  teardown { Firmware.reset_config! }

  OLD = { 'stm32' => '1.4.0', 'stm32_assets' => '1.4.0', 'nrf_app' => '1.2.0', 'nrf_net' => '1.1.0' }.freeze

  def check(query = {}, headers = {})
    get '/api/v1/firmware/check', params: { hw: 'V114', device: DEVICE, app_version: '2.7.0' }.merge(query),
                                  headers: { 'REMOTE_ADDR' => '203.0.113.9' }.merge(headers)
  end

  def offered
    json['bundle'] && json['bundle']['version']
  end

  def components
    json['bundle']['images'].map { |i| i['component'] }
  end

  test 'offers the newest published bundle with only the changed images, in install order' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    bundle = create_firmware_bundle(version: '1.5.0', release_notes: 'Smoother pads', min_app_version: '2.6.0',
                                    images: OLD.merge('stm32' => '1.5.0', 'nrf_app' => '1.3.0'))

    check(OLD)
    assert_response :success
    assert_equal 'no-store', response.headers['Cache-Control']
    assert_equal '1.5.0', offered
    assert_equal bundle.id, json['bundle']['id']
    assert_equal 'Smoother pads', json['bundle']['notes']
    assert_equal '2.6.0', json['bundle']['min_app_version']
    assert_equal %w[nrf_app stm32_assets stm32], components, 'nrf_net unchanged; assets ride with stm32'
    stm32 = json['bundle']['images'].last
    image = bundle.images.find_by(component: 'stm32')
    assert_equal [image.version, image.size, image.sha256, 'dev-1'],
                 stm32.values_at('version', 'size', 'sha256', 'signature_key_id')
    assert stm32['url'].present?
    assert Time.iso8601(stm32['url_expires_at']) > 50.minutes.from_now
    refute json['app_update_required']
    assert_nil json['revoked']
  end

  test 'a device without versions (recovery) gets every image' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    check
    assert_equal %w[nrf_net nrf_app stm32_assets stm32], components
  end

  test 'up to date: bundle null' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    check(OLD)
    assert_response :success
    assert_nil json['bundle']
    refute json['app_update_required']
  end

  test 'drafts and other hardware revisions are never offered' do
    create_firmware_bundle(version: '1.6.0', images: OLD.merge('stm32' => '1.6.0'), state: 'draft')
    create_firmware_bundle(version: '1.7.0', images: OLD.merge('stm32' => '1.7.0'), hw_rev: 'V115')
    check(OLD)
    assert_nil json['bundle']
  end

  test 'kill switch: a paused bundle is offered to nobody, at once' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    bundle = create_firmware_bundle(version: '1.5.0', images: OLD.merge('stm32' => '1.5.0'))
    check(OLD)
    assert_equal '1.5.0', offered

    bundle.pause!
    check(OLD)
    assert_nil json['bundle'], 'a device on 1.4.0 keeps it'

    check
    assert_equal '1.4.0', offered, 'a recovering device gets the newest good bundle'
  end

  test 'revoked: devices on it are told and offered the newest good bundle' do
    create_firmware_bundle(version: '1.4.0', images: OLD, release_notes: 'Good one')
    create_firmware_bundle(version: '1.5.0', images: OLD.merge('stm32' => '1.5.0', 'stm32_assets' => '1.5.0'),
                           release_notes: 'Bricks the pads', state: 'revoked')
    check(OLD.merge('stm32' => '1.5.0', 'stm32_assets' => '1.5.0'))
    assert_equal({ 'version' => '1.5.0', 'notes' => 'Bricks the pads' }, json['revoked'])
    assert_equal '1.4.0', offered
    assert_equal %w[stm32_assets stm32], components
    assert_equal %w[1.4.0 1.4.0], json['bundle']['images'].map { |i| i['version'] }
  end

  test 'channels: stable sees stable, beta sees beta and stable, internal sees everything' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    create_firmware_bundle(version: '1.5.0-beta.1', images: OLD.merge('stm32' => '1.5.0-beta.1'), channel: 'beta')
    create_firmware_bundle(version: '1.6.0-dev.3', images: OLD.merge('stm32' => '1.6.0-dev.3'), channel: 'internal')

    check(OLD)
    assert_nil json['bundle']
    check(OLD.merge(channel: 'beta'))
    assert_equal '1.5.0-beta.1', offered
    check(OLD.merge(channel: 'internal'))
    assert_equal '1.6.0-dev.3', offered
  end

  test 'a beta device gets stable when stable is newer' do
    create_firmware_bundle(version: '1.5.0-beta.1', images: OLD.merge('stm32' => '1.5.0-beta.1'), channel: 'beta')
    create_firmware_bundle(version: '1.5.0', images: OLD.merge('stm32' => '1.5.0'))
    check(OLD.merge(channel: 'beta'))
    assert_equal '1.5.0', offered
  end

  test 'leaving beta never downgrades' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    create_firmware_bundle(version: '1.5.0-beta.1', images: OLD.merge('stm32' => '1.5.0-beta.1'), channel: 'beta')
    check(OLD.merge('stm32' => '1.5.0-beta.1', channel: 'stable'))
    assert_nil json['bundle']
  end

  test 'rollout: devices outside the bucket are not offered the bundle' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    create_firmware_bundle(version: '1.5.0', images: OLD.merge('stm32' => '1.5.0'), rollout_percent: 20)

    check(OLD.merge(device: device_in_rollout('1.5.0', 20, inside: true)))
    assert_equal '1.5.0', offered
    check(OLD.merge(device: device_in_rollout('1.5.0', 20, inside: false)))
    assert_nil json['bundle']
    check(OLD.merge(device: nil))
    assert_nil json['bundle'], 'without a device hash only 100 % rollouts are offered'
  end

  test 'rollout: a device outside the newest bundle gets the older one it does not have' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    create_firmware_bundle(version: '1.5.0', images: OLD.merge('stm32' => '1.5.0'), rollout_percent: 5)
    check(OLD.merge('stm32' => '1.3.0', 'stm32_assets' => '1.3.0', device: device_in_rollout('1.5.0', 5, inside: false)))
    assert_equal '1.4.0', offered
  end

  test 'lowering a rollout never downgrades devices already on the bundle' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    create_firmware_bundle(version: '1.5.0', images: OLD.merge('stm32' => '1.5.0'), rollout_percent: 0)
    check(OLD.merge('stm32' => '1.5.0'))
    assert_nil json['bundle']
  end

  test 'min app version: an old app is told to update and gets the newest bundle it can install' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    create_firmware_bundle(version: '1.5.0', images: OLD.merge('stm32' => '1.5.0'), min_app_version: '2.8.0')
    old = OLD.merge('stm32' => '1.3.0', 'stm32_assets' => '1.3.0')

    check(old.merge(app_version: '2.7.0'))
    assert json['app_update_required']
    assert_equal '2.8.0', json['min_app_version']
    assert_equal '1.4.0', offered

    check(OLD.merge(app_version: '2.7.0'))
    assert json['app_update_required']
    assert_nil json['bundle']

    check(old.merge(app_version: '2.8.0'))
    refute json['app_update_required']
    assert_nil json['min_app_version']
    assert_equal '1.5.0', offered
  end

  test 'a lower security epoch than the current bundle is never offered' do
    create_firmware_bundle(version: '1.4.0', images: OLD, security_epoch: 2)
    create_firmware_bundle(version: '1.5.0', images: OLD.merge('stm32' => '1.5.0'), security_epoch: 1)
    check(OLD)
    assert_nil json['bundle']
  end

  test 'bad parameters are 422 with fields' do
    get '/api/v1/firmware/check', params: { channel: 'stable' }
    assert_response :unprocessable_entity
    assert json['fields']['hw'].any?

    check(channel: 'nightly')
    assert_response :unprocessable_entity
    assert json['fields']['channel'].any?

    check(device: 'not-a-hash')
    assert_response :unprocessable_entity
    assert json['fields']['device'].any?

    check(stm32: 'x' * 65)
    assert_response :unprocessable_entity
  end

  test 'rate-limited per IP' do
    Firmware.config.rate_limits[:check_ip] = { limit: 2, window: 1.hour }
    2.times { check }
    assert_response :success
    check
    assert_response :too_many_requests
    check({}, 'REMOTE_ADDR' => '198.51.100.4')
    assert_response :success
  end

  test 'the recovery web page origin is allowed by CORS' do
    create_firmware_bundle(version: '1.4.0', images: OLD)
    check({}, 'Origin' => 'https://beeper.buzz')
    assert_equal 'https://beeper.buzz', response.headers['Access-Control-Allow-Origin']

    process :options, '/api/v1/firmware/check',
            headers: { 'Origin' => 'https://www.beeper.buzz', 'Access-Control-Request-Method' => 'GET' }
    assert_equal 'https://www.beeper.buzz', response.headers['Access-Control-Allow-Origin']

    check({}, 'Origin' => 'https://evil.example')
    assert_nil response.headers['Access-Control-Allow-Origin']
  end
end
