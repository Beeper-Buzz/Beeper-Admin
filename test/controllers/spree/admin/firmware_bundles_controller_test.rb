require 'test_helper'

# Admin "Firmware" tab: drafts, image upload, publish / pause / resume / revoke, rollout, reports.
class Spree::Admin::FirmwareBundlesControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @admin = make_admin(create(:user))
  end

  teardown { Warden.test_reset! }

  def sign_in(user)
    login_as(user, scope: :spree_user)
  end

  test 'admins only' do
    bundle = create_firmware_bundle(version: '1.4.0', state: 'draft')
    get '/admin/firmware'
    refute_includes response.body, "firmware_bundle_#{bundle.id}"

    sign_in(create(:user))
    get '/admin/firmware'
    refute_includes response.body, "firmware_bundle_#{bundle.id}"
    post "/admin/firmware/#{bundle.id}/publish"
    assert bundle.reload.draft?
    post '/admin/firmware', params: { firmware_bundle: { hw_rev: 'V114', version: '9.9.9' } }
    assert_equal 1, FirmwareBundle.count
  end

  test 'the sidebar has a Firmware tab; the index lists bundles with report counts' do
    bundle = create_firmware_bundle(version: '1.4.0')
    FirmwareReport.create!(bundle: bundle, device_hash: DEVICE, result: 'failed', stage: 'transfer')
    sign_in(@admin)
    get '/admin/firmware'
    assert_response :success
    assert_includes response.body, 'sidebarFirmware'
    assert_includes response.body, "firmware_bundle_#{bundle.id}"
    assert_includes response.body, 'failed 1'
  end

  test 'create a draft, upload images, publish' do
    sign_in(@admin)
    post '/admin/firmware', params: { firmware_bundle: { hw_rev: 'V114', version: '1.5.0', channel: 'beta',
                                                         rollout_percent: 10, release_notes: 'Notes' } }
    bundle = FirmwareBundle.last
    assert_redirected_to "/admin/firmware/#{bundle.id}"
    assert_equal ['draft', @admin.email], [bundle.state, bundle.created_by]

    %w[stm32 stm32_assets].each do |component|
      bytes = image_bytes(component, '1.5.0')
      post "/admin/firmware/#{bundle.id}/images",
           params: { firmware_image: { component: component, version: '1.5.0', signature_key_id: 'stm32-dev',
                                       sha256: sha256_hex(bytes), file: firmware_upload(bytes) } }
      assert_redirected_to "/admin/firmware/#{bundle.id}"
    end
    assert_equal 2, bundle.images.count

    get "/admin/firmware/#{bundle.id}"
    assert_response :success
    assert_includes response.body, 'firmware_image_form'
    assert_includes response.body, 'publish_firmware_bundle'

    post "/admin/firmware/#{bundle.id}/publish"
    assert bundle.reload.published?

    get "/admin/firmware/#{bundle.id}"
    refute_includes response.body, 'firmware_image_form', 'no uploads once published'
    assert_includes response.body, 'pause_firmware_bundle'
  end

  test 'a bad image upload shows the error and stores nothing' do
    bundle = create_firmware_bundle(version: '1.5.0', state: 'draft', images: {})
    sign_in(@admin)
    post "/admin/firmware/#{bundle.id}/images",
         params: { firmware_image: { component: 'stm32', version: '1.5.0', signature_key_id: 'k', sha256: 'a' * 64,
                                     file: firmware_upload('bytes') } }
    assert_match(/does not match/, flash[:error])
    assert_equal 0, bundle.images.count
  end

  test 'publishing an incomplete draft is refused with the reason' do
    bundle = create_firmware_bundle(version: '1.5.0', state: 'draft', images: { 'stm32' => '1.5.0' })
    sign_in(@admin)
    post "/admin/firmware/#{bundle.id}/publish"
    assert bundle.reload.draft?
    assert_match(/ship together/, flash[:error])
  end

  test 'pause (kill switch), resume, revoke' do
    bundle = create_firmware_bundle(version: '1.5.0')
    sign_in(@admin)
    post "/admin/firmware/#{bundle.id}/pause"
    assert bundle.reload.paused?
    post "/admin/firmware/#{bundle.id}/publish"
    assert bundle.reload.published?
    post "/admin/firmware/#{bundle.id}/revoke"
    assert bundle.reload.revoked?
    post "/admin/firmware/#{bundle.id}/publish"
    assert bundle.reload.revoked?
  end

  test 'rollout and channel change on a published bundle; its version does not' do
    bundle = create_firmware_bundle(version: '1.5.0', rollout_percent: 5)
    sign_in(@admin)
    patch "/admin/firmware/#{bundle.id}", params: { firmware_bundle: { rollout_percent: 50, channel: 'beta', version: '9.0.0' } }
    bundle.reload
    assert_equal [50, 'beta', '1.5.0'], [bundle.rollout_percent, bundle.channel, bundle.version]
  end

  test 'images of a published bundle cannot be removed' do
    bundle = create_firmware_bundle(version: '1.5.0')
    sign_in(@admin)
    delete "/admin/firmware/#{bundle.id}/images/#{bundle.images.first.id}"
    assert_equal 2, bundle.images.count
  end

  test 'drafts can be deleted, released bundles cannot' do
    draft = create_firmware_bundle(version: '1.6.0', state: 'draft')
    released = create_firmware_bundle(version: '1.5.0')
    sign_in(@admin)
    delete "/admin/firmware/#{draft.id}"
    refute FirmwareBundle.exists?(draft.id)
    delete "/admin/firmware/#{released.id}"
    assert FirmwareBundle.exists?(released.id)
  end

  test 'the bundle page shows report counts and the latest reports' do
    bundle = create_firmware_bundle(version: '1.5.0')
    FirmwareReport.create!(bundle: bundle, device_hash: DEVICE, result: 'ok', component: 'stm32')
    FirmwareReport.create!(bundle: bundle, device_hash: DEVICE, result: 'rolled_back', component: 'stm32', stage: 'trial_boot')
    sign_in(@admin)
    get "/admin/firmware/#{bundle.id}"
    assert_response :success
    assert_includes response.body, 'rolled_back 1'
    assert_includes response.body, 'trial_boot'
    assert_equal 2, response.body.scan(/id="firmware_report_\d+"/).size
  end
end
