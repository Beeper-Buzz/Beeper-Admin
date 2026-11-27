require 'test_helper'

# config/initializers/beeper_admin_native_resources.rb: the Δ8 firmware types in the Spree Admin
# Native app, through /api/admin_native/v1/resources with an admin API key.
class BeeperAdminNativeResourcesTest < ActionDispatch::IntegrationTest
  BASE = '/api/admin_native/v1/resources'.freeze
  SECRET_LOOKING = /password|token|secret|digest|encrypted|api_key|salt|otp|private_key|credentials/i.freeze
  TYPES = %w[firmware_bundles firmware_images firmware_reports].freeze

  setup do
    @admin = make_admin(create(:user))
    @admin.generate_spree_api_key!
  end

  # values is positional so a literal hash isn't taken for keywords on Ruby 2.7.
  def call(method, path, values = nil, api_key = @admin.spree_api_key)
    headers = { 'X-Spree-Token' => api_key, 'CONTENT_TYPE' => 'application/json' }
    send(method, "#{BASE}#{path}", params: values ? { values: values }.to_json : nil, headers: headers)
    response.body.empty? ? {} : JSON.parse(response.body)
  end

  def run_action(bundle, action)
    call(:post, "/firmware_bundles/#{bundle.id}/actions/#{action}")
  end

  def actions_of(bundle)
    call(:get, "/firmware_bundles/#{bundle.id}").dig('data', 'actions')
  end

  test 'the firmware types are in the manifest under Firmware, admins only' do
    data = call(:get, '')['data']
    assert_equal 200, response.status
    firmware = data.select { |d| TYPES.include?(d['key']) }
    assert_equal TYPES.sort, firmware.map { |d| d['key'] }.sort
    assert(firmware.all? { |d| d['group'] == 'Firmware' })
    firmware.flat_map { |d| d['fields'] }.each { |f| refute_match SECRET_LOOKING, f['name'] }
    refute_includes firmware.find { |d| d['key'] == 'firmware_reports' }['fields'].map { |f| f['name'] }, 'user_id'

    call(:get, '/firmware_bundles', nil, nil)
    assert_equal 401, response.status
    customer = create(:user)
    customer.generate_spree_api_key!
    call(:get, '/firmware_bundles', nil, customer.spree_api_key)
    assert_equal 401, response.status
  end

  test 'homepage sections carry their page, as in the admin' do
    type = call(:get, '')['data'].find { |d| d['key'] == 'homepage_sections' }
    field = type['fields'].find { |f| f['name'] == 'page_key' }
    assert_equal ['enum', HomepageSection::PAGES], [field['type'], field['options']]
    assert_includes type['filters'].map { |f| f['name'] }, 'page_key'

    body = call(:post, '/homepage_sections', { title: 'How it works', section_type: 'steps', page_key: 'creators' })
    assert_equal 201, response.status, response.body
    assert_equal 'creators', HomepageSection.find(body.dig('data', 'id')).page_key
    HomepageSection.create!(title: 'Hero', section_type: 'hero', position: 1)
    body = call(:get, '/homepage_sections?filter[page_key]=creators')
    assert_equal ['How it works'], body['data'].map { |s| s['title'] }
    call(:post, '/homepage_sections', { title: 'Nowhere', section_type: 'hero', page_key: 'nowhere' })
    assert_equal 422, response.status
  end

  test 'bundles, images and reports list and show' do
    bundle = create_firmware_bundle(version: '1.4.0')
    report = FirmwareReport.create!(bundle: bundle, device_hash: FirmwareTestHelper::DEVICE, result: 'failed',
                                    stage: 'transfer', user: create(:user))
    image = bundle.images.first
    { 'firmware_bundles' => bundle, 'firmware_images' => image, 'firmware_reports' => report }.each do |key, record|
      body = call(:get, "/#{key}")
      assert_equal 200, response.status, "#{key}: #{response.body}"
      assert_includes body['data'].map { |r| r['id'] }, record.id.to_s
      body = call(:get, "/#{key}/#{record.id}")
      assert_equal 200, response.status, "#{key}: #{response.body}"
      body.dig('data', 'values').each_key { |name| refute_match SECRET_LOOKING, name }
    end
    body = call(:get, "/firmware_images/#{image.id}")
    assert_equal({ 'id' => bundle.id.to_s, 'title' => bundle.label }, body.dig('data', 'values', 'firmware_bundle_id'))
    body = call(:get, "/firmware_reports?filter[result]=failed&q=#{FirmwareTestHelper::DEVICE[0, 8]}")
    assert_equal [report.id.to_s], body['data'].map { |r| r['id'] }
    refute call(:get, "/firmware_reports/#{report.id}").dig('data', 'values').key?('user_id')
  end

  test 'a draft is created, edited and deleted; a released bundle keeps its identity' do
    body = call(:post, '/firmware_bundles', { hw_rev: 'V114', version: '2.0.0', channel: 'beta', rollout_percent: 10,
                                              state: 'published' })
    assert_equal 201, response.status, response.body
    draft = FirmwareBundle.find(body.dig('data', 'id'))
    assert draft.draft?, 'new bundles are drafts'
    assert_equal %w[publish], body.dig('data', 'actions')
    call(:patch, "/firmware_bundles/#{draft.id}", { version: '2.0.1' })
    assert_equal 200, response.status
    call(:delete, "/firmware_bundles/#{draft.id}")
    assert_equal 204, response.status

    released = create_firmware_bundle(version: '1.5.0')
    call(:patch, "/firmware_bundles/#{released.id}", { version: '9.9.9' })
    assert_equal 422, response.status
    call(:patch, "/firmware_bundles/#{released.id}", { rollout_percent: 50, release_notes: 'Faster pairing' })
    assert_equal 200, response.status, response.body
    assert_equal [50, '1.5.0'], [released.reload.rollout_percent, released.version]
    call(:delete, "/firmware_bundles/#{released.id}")
    assert_equal 422, response.status
    assert FirmwareBundle.exists?(released.id)
  end

  test 'publish, pause, resume and revoke follow the bundle states' do
    empty = create_firmware_bundle(version: '3.0.0', images: {}, state: 'draft')
    body = run_action(empty, 'publish')
    assert_equal 422, response.status, 'a bundle without images is not published'
    assert_includes body.dig('error', 'message'), 'at least one image'
    assert empty.reload.draft?

    bundle = create_firmware_bundle(version: '3.1.0', state: 'draft')
    run_action(bundle, 'publish')
    assert_equal 200, response.status, response.body
    assert bundle.reload.published?
    assert_equal %w[pause revoke], actions_of(bundle)
    run_action(bundle, 'publish')
    assert_equal 422, response.status

    run_action(bundle, 'pause')
    assert_equal 200, response.status
    assert bundle.reload.paused?
    assert_equal %w[resume revoke], actions_of(bundle)
    body = run_action(bundle, 'resume')
    assert_equal 200, response.status
    assert_includes body['message'], 'resumed'
    assert bundle.reload.published?

    run_action(bundle, 'revoke')
    assert_equal 200, response.status
    assert bundle.reload.revoked?
    assert_equal [], actions_of(bundle)
  end

  test 'images are removed only from drafts and never written from the app' do
    draft = create_firmware_bundle(version: '4.0.0', state: 'draft')
    released = create_firmware_bundle(version: '4.1.0')
    call(:post, '/firmware_images', { firmware_bundle_id: draft.id, component: 'stm32', version: '4.0.0' })
    assert_equal 403, response.status
    call(:patch, "/firmware_images/#{draft.images.first.id}", { version: '4.0.1' })
    assert_equal 403, response.status
    call(:delete, "/firmware_images/#{released.images.first.id}")
    assert_equal 422, response.status
    call(:delete, "/firmware_images/#{draft.images.first.id}")
    assert_equal 204, response.status
  end

  test 'reports are read only' do
    bundle = create_firmware_bundle(version: '5.0.0')
    report = FirmwareReport.create!(bundle: bundle, device_hash: FirmwareTestHelper::DEVICE, result: 'ok')
    call(:post, '/firmware_reports', { result: 'ok' })
    assert_equal 403, response.status
    call(:patch, "/firmware_reports/#{report.id}", { result: 'failed' })
    assert_equal 403, response.status
    call(:delete, "/firmware_reports/#{report.id}")
    assert_equal 403, response.status
  end
end
