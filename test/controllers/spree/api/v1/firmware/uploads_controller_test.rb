require 'test_helper'

# POST /api/v1/admin/firmware/bundles: CI creates draft bundles with a scoped token.
class Spree::Api::V1::Firmware::UploadsControllerTest < ActionDispatch::IntegrationTest
  TOKEN = 'ci-token-0123456789abcdef0123456789abcdef'.freeze

  setup { Firmware.config.upload_tokens = "old-token-that-is-long-enough-000000000,#{TOKEN}" }
  teardown { Firmware.reset_config! }

  def image_fields(component, version, bytes = image_bytes(component, version), overrides = {})
    { file: firmware_upload(bytes, "#{component}.bin"), version: version, sha256: sha256_hex(bytes),
      signature_key_id: 'dev-1' }.merge(overrides)
  end

  def upload(params, token = TOKEN)
    headers = token ? { 'Authorization' => "Bearer #{token}" } : {}
    post '/api/v1/admin/firmware/bundles', params: params, headers: headers
  end

  def bundle_params(overrides = {})
    {
      hw: 'V114', version: '1.5.0', release_notes: 'From CI',
      images: {
        stm32: image_fields('stm32', '1.5.0'),
        stm32_assets: image_fields('stm32_assets', '1.5.0', image_bytes('stm32_assets', '1.5.0'), content_hash: 'abcdef0123456789'),
        nrf_app: image_fields('nrf_app', '1.3.0', image_bytes('nrf_app', '1.3.0'), link_proto: '2', app_proto: '1')
      }
    }.merge(overrides)
  end

  test 'creates a draft on the internal channel with every image' do
    upload(bundle_params)
    assert_response :created
    bundle = FirmwareBundle.find(json['id'])
    assert_equal %w[V114 1.5.0 internal draft], [bundle.hw_rev, bundle.version, bundle.channel, bundle.state]
    assert_equal [0, 'ci', 'From CI'], [bundle.rollout_percent, bundle.created_by, bundle.release_notes]
    assert_equal %w[nrf_app stm32_assets stm32], json['images'].map { |i| i['component'] }
    assert_equal "/admin/firmware/#{bundle.id}", json['admin_path']
    nrf = bundle.images.find_by(component: 'nrf_app')
    assert_equal [2, 1], [nrf.link_proto, nrf.app_proto]
    assert_equal 'abcdef0123456789', bundle.images.find_by(component: 'stm32_assets').content_hash
    assert bundle.images.all? { |i| i.file.attached? }
  end

  test 'the channel can be chosen, the state cannot' do
    upload(bundle_params(channel: 'beta', state: 'published', rollout_percent: 100))
    assert_response :created
    bundle = FirmwareBundle.find(json['id'])
    assert_equal %w[beta draft], [bundle.channel, bundle.state]
    assert_equal 0, bundle.rollout_percent
  end

  test 'no, a wrong or an unset token is 401 and creates nothing' do
    upload(bundle_params, nil)
    assert_response :unauthorized
    upload(bundle_params, 'wrong-token-0123456789abcdef0123456789')
    assert_response :unauthorized

    Firmware.config.upload_tokens = nil
    upload(bundle_params, '')
    assert_response :unauthorized
    assert_equal 0, FirmwareBundle.count
  end

  test 'a user api key or bearer is not a CI token' do
    user = create(:user)
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    upload(bundle_params, token_for(user))
    assert_response :unauthorized
  end

  test 'a sha256 that does not match the bytes is 422 and keeps nothing' do
    blobs = ActiveStorage::Blob.count
    params = bundle_params
    params[:images][:stm32][:sha256] = 'f' * 64
    upload(params)
    assert_response :unprocessable_entity
    assert json['fields']['stm32.sha256'].any?
    assert_equal 0, FirmwareBundle.count
    assert_equal 0, FirmwareImage.count
    assert_equal blobs, ActiveStorage::Blob.count
  end

  test 'an unsigned radio image is 422' do
    params = bundle_params
    params[:images][:nrf_app] = image_fields('nrf_app', '1.3.0', mcuboot_bytes(version: '1.3.0', signed: false))
    upload(params)
    assert_response :unprocessable_entity
    assert json['fields']['nrf_app.file'].any?
    assert_equal 0, FirmwareBundle.count
  end

  test 'sha256 is required from CI, and so is a file' do
    params = bundle_params
    params[:images][:stm32].delete(:sha256)
    upload(params)
    assert_response :unprocessable_entity
    assert json['fields']['stm32.sha256'].any?

    params = bundle_params
    params[:images][:stm32].delete(:file)
    upload(params)
    assert_response :unprocessable_entity
    assert json['fields']['stm32.file'].any?
  end

  test 'unknown components and missing images are 422' do
    upload(bundle_params(images: { bootloader: image_fields('stm32', '1.5.0') }))
    assert_response :unprocessable_entity
    upload(bundle_params(images: nil))
    assert_response :unprocessable_entity
    assert_equal 0, FirmwareBundle.count
  end

  test 'an existing version for that hardware and channel is 409' do
    create_firmware_bundle(version: '1.5.0', channel: 'internal')
    upload(bundle_params)
    assert_response :conflict
    assert_equal 1, FirmwareBundle.count
  end

  test 'bad bundle fields are 422' do
    upload(bundle_params(version: '1.5'))
    assert_response :unprocessable_entity
    assert json['fields']['version'].any?
  end
end
