require 'test_helper'

class FirmwareBundleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def draft(attrs = {})
    FirmwareBundle.new({ hw_rev: 'V114', version: '1.4.0', channel: 'stable' }.merge(attrs))
  end

  test 'defaults: internal channel, draft, 0 % rollout, epoch 0' do
    bundle = FirmwareBundle.create!(hw_rev: 'V114', version: '1.0.0')
    assert_equal %w[internal draft], [bundle.channel, bundle.state]
    assert_equal [0, 0], [bundle.rollout_percent, bundle.security_epoch]
  end

  test 'version and min_app_version must be semver' do
    assert draft(version: '1.4.0-rc.1+7').valid?
    %w[1.4 v1.4.0 1.4.0.1 01.4.0].each do |bad|
      refute draft(version: bad).valid?, bad
    end
    refute draft(min_app_version: '2.7').valid?
    assert draft(min_app_version: '2.7.0').valid?
  end

  test 'channel, state, rollout and hw_rev are checked' do
    refute draft(channel: 'nightly').valid?
    refute draft(state: 'live').valid?
    refute draft(rollout_percent: 101).valid?
    refute draft(rollout_percent: -1).valid?
    refute draft(hw_rev: 'V1 14').valid?
  end

  test 'a version is unique per hardware revision and channel' do
    draft.save!
    dup = draft
    refute dup.valid?
    assert dup.errors.of_kind?(:version, :taken)
    assert draft(channel: 'beta').valid?
    assert draft(hw_rev: 'V115').valid?
  end

  test 'publishing needs images, with stm32 and stm32_assets together' do
    bundle = draft
    bundle.save!
    refute bundle.publish!
    assert_match(/at least one image/, bundle.errors.full_messages.to_sentence)

    Firmware::ImageUpload.call(bundle, temp_file(image_bytes('stm32', '1.4.0')).path,
                               component: 'stm32', version: '1.4.0', signature_key_id: 'k')
    refute bundle.reload.publish!
    assert_match(/ship together/, bundle.errors.full_messages.to_sentence)

    Firmware::ImageUpload.call(bundle, temp_file(image_bytes('stm32_assets', '1.4.0')).path,
                               component: 'stm32_assets', version: '1.4.0', signature_key_id: 'k')
    assert bundle.reload.publish!, bundle.errors.full_messages.to_sentence
    assert bundle.published?
    assert bundle.published_at.present?
  end

  test 'a radio-only bundle can be published' do
    bundle = create_firmware_bundle(version: '1.0.1', images: { 'nrf_app' => '1.0.1' })
    assert bundle.published?
  end

  test 'state changes: publish, pause, resume, revoke; revoked is final' do
    bundle = create_firmware_bundle(version: '1.4.0')
    first_published = bundle.published_at
    refute bundle.publish!

    assert bundle.pause!
    assert bundle.paused?
    refute bundle.pause!
    travel 1.hour do
      assert bundle.publish!
    end
    assert_equal first_published.to_i, bundle.reload.published_at.to_i, 'resuming keeps the first publish time'

    assert bundle.revoke!
    refute bundle.publish!
    refute bundle.pause!
    refute bundle.revoke!
  end

  test 'hardware, version and security epoch are frozen once out of draft; rollout and notes are not' do
    bundle = create_firmware_bundle(version: '1.4.0')
    refute bundle.update(version: '1.4.1')
    refute bundle.reload.update(hw_rev: 'V115')
    refute bundle.reload.update(security_epoch: 2)
    assert bundle.reload.update(rollout_percent: 25, release_notes: 'Fixes', channel: 'beta', min_app_version: '2.8.0')
  end

  test 'only drafts can be deleted, with their images and files' do
    released = create_firmware_bundle(version: '1.4.0')
    refute released.destroy
    assert FirmwareBundle.exists?(released.id)

    drafted = create_firmware_bundle(version: '1.5.0', state: 'draft')
    blob_ids = drafted.images.map { |i| i.file.blob.id }
    perform_enqueued_jobs { assert drafted.destroy }
    refute FirmwareImage.exists?(firmware_bundle_id: drafted.id)
    refute ActiveStorage::Blob.where(id: blob_ids).exists?
  end

  test 'newest first by semver, not by string' do
    list = %w[1.9.0 1.10.0 1.10.0-rc.1 2.0.0].map { |v| FirmwareBundle.new(version: v) }
    assert_equal %w[2.0.0 1.10.0 1.10.0-rc.1 1.9.0], FirmwareBundle.sort_newest_first(list).map(&:version)
  end

  test 'requires_newer_app? compares against min_app_version' do
    bundle = draft(min_app_version: '2.7.0')
    assert bundle.requires_newer_app?('2.6.9')
    refute bundle.requires_newer_app?('2.7.0')
    refute bundle.requires_newer_app?('2.10.0')
    refute bundle.requires_newer_app?(nil), 'no app version (recovery page): no gate'
    assert bundle.requires_newer_app?('garbage')
    refute draft.requires_newer_app?('0.1.0')
  end

  test 'images_to_install skips unchanged components, keeps pairs together, in install order' do
    bundle = create_firmware_bundle(version: '1.5.0', images: { 'stm32' => '1.5.0', 'stm32_assets' => '1.4.0',
                                                                'nrf_app' => '1.2.0', 'nrf_net' => '1.1.0' })
    current = { 'stm32' => '1.4.0', 'stm32_assets' => '1.4.0', 'nrf_app' => '1.1.0', 'nrf_net' => '1.1.0' }
    assert_equal %w[nrf_app stm32_assets stm32], bundle.images_to_install(current).map(&:component)
    assert_equal %w[nrf_net nrf_app stm32_assets stm32], bundle.images_to_install({}).map(&:component)
  end
end
