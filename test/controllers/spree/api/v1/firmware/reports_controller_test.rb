require 'test_helper'

# POST /api/v1/firmware/reports: install results, optional bearer, hashed device ids only.
class Spree::Api::V1::Firmware::ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bundle = create_firmware_bundle(version: '1.5.0')
    @user = create(:user)
  end

  teardown { Firmware.reset_config! }

  def fields(overrides = {})
    {
      device: DEVICE, bundle_id: @bundle.id, component: 'stm32', from_version: '1.4.0', to_version: '1.5.0',
      result: 'rolled_back', stage: 'trial_boot', error_code: 'E_TRIAL_TIMEOUT', duration_ms: 41_250,
      app_version: '2.7.0', platform: 'ios', phone_model: 'iPhone15,2'
    }.merge(overrides)
  end

  def send_report(params = fields, headers = {})
    post '/api/v1/firmware/reports', params: params, headers: { 'REMOTE_ADDR' => '203.0.113.7' }.merge(headers), as: :json
  end

  test 'an anonymous report is stored with every field' do
    send_report
    assert_response :created
    report = FirmwareReport.find(json['id'])
    assert_equal({ 'id' => report.id }, json)
    assert_equal @bundle, report.bundle
    assert_nil report.user_id
    assert_equal [DEVICE, 'stm32', '1.4.0', '1.5.0', 'rolled_back', 'trial_boot', 'E_TRIAL_TIMEOUT', 41_250, '2.7.0', 'ios', 'iPhone15,2'],
                 report.attributes.values_at('device_hash', 'component', 'from_version', 'to_version', 'result', 'stage',
                                             'error_code', 'duration_ms', 'app_version', 'platform', 'phone_model')
  end

  test 'a valid bearer links the user; an invalid one files it anonymously' do
    send_report(fields, auth(@user))
    assert_response :created
    assert_equal @user.id, FirmwareReport.find(json['id']).user_id

    send_report(fields, bearer('expired-or-wrong'))
    assert_response :created
    assert_nil FirmwareReport.find(json['id']).user_id
  end

  test 'the web recovery page reports too' do
    send_report(fields(platform: 'web', app_version: nil, phone_model: nil, result: 'ok'))
    assert_response :created
  end

  test 'a raw device id, an unknown bundle or a bad result is 422' do
    send_report(fields(device: '0123456789ABCDEF01234567'))
    assert_response :unprocessable_entity
    assert json['fields']['device_hash'].any?

    send_report(fields(bundle_id: 0))
    assert_response :unprocessable_entity
    assert json['fields']['bundle'].any?

    send_report(fields(result: 'great'))
    assert_response :unprocessable_entity
    assert json['fields']['result'].any?

    send_report(fields(component: 'bootloader'))
    assert_response :unprocessable_entity
    assert_equal 0, FirmwareReport.count
  end

  test 'rate-limited per device and per IP' do
    Firmware.config.rate_limits[:report_device] = { limit: 2, window: 1.day }
    2.times { send_report }
    assert_response :created
    send_report
    assert_response :too_many_requests
    send_report(fields(device: 'cd' * 32))
    assert_response :created, 'another device from the same IP'

    Firmware.config.rate_limits[:report_ip] = { limit: 1, window: 1.hour }
    send_report(fields(device: 'ef' * 32), 'REMOTE_ADDR' => '198.51.100.1')
    assert_response :created
    send_report(fields(device: '12' * 32), 'REMOTE_ADDR' => '198.51.100.1')
    assert_response :too_many_requests
  end

  test 'CORS preflight from the recovery page' do
    process :options, '/api/v1/firmware/reports',
            headers: { 'Origin' => 'https://beeper.buzz', 'Access-Control-Request-Method' => 'POST',
                       'Access-Control-Request-Headers' => 'content-type' }
    assert_equal 'https://beeper.buzz', response.headers['Access-Control-Allow-Origin']
  end
end
