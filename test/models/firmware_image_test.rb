require 'test_helper'

class FirmwareImageTest < ActiveSupport::TestCase
  setup do
    @bundle = FirmwareBundle.create!(hw_rev: 'V114', version: '1.4.0', channel: 'stable')
  end

  def upload(component, bytes, attrs = {})
    Firmware::ImageUpload.call(@bundle, temp_file(bytes).path,
                               { component: component, version: '1.4.0', signature_key_id: 'stm32-release' }.merge(attrs))
  end

  test 'size and sha256 come from the file when not declared' do
    bytes = image_bytes('stm32', '1.4.0')
    image = upload('stm32', bytes)
    assert image.persisted?, image.errors.full_messages.to_sentence
    assert_equal bytes.bytesize, image.size
    assert_equal sha256_hex(bytes), image.sha256
    assert image.file.attached?
    assert_equal bytes.bytesize, image.file.blob.byte_size
    assert_equal bytes, image.file.download
  end

  test 'a declared sha256 or size that differs from the bytes is refused, and nothing is stored' do
    bytes = image_bytes('stm32', '1.4.0')
    blobs = ActiveStorage::Blob.count
    image = upload('stm32', bytes, sha256: 'f' * 64)
    refute image.persisted?
    assert image.errors.of_kind?(:sha256, 'does not match the uploaded file')

    image = upload('stm32', bytes, size: bytes.bytesize + 1, sha256: sha256_hex(bytes).upcase)
    refute image.persisted?
    assert image.errors.include?(:size)
    assert_equal blobs, ActiveStorage::Blob.count
    assert_equal 0, @bundle.images.count
  end

  test 'a matching declared sha256 (any case) is accepted' do
    bytes = image_bytes('stm32', '1.4.0')
    assert upload('stm32', bytes, sha256: sha256_hex(bytes).upcase, size: bytes.bytesize).persisted?
  end

  test 'signature key id and semver version are required; one image per component' do
    bytes = image_bytes('stm32', '1.4.0')
    refute upload('stm32', bytes, signature_key_id: nil).persisted?
    refute upload('stm32', bytes, version: '1.4').persisted?
    refute upload('bootloader', bytes).persisted?
    assert upload('stm32', bytes).persisted?
    dup = upload('stm32', bytes)
    refute dup.persisted?
    assert dup.errors.of_kind?(:component, 'is already in this bundle')
  end

  test 'radio images must be signed MCUboot images of the declared version' do
    unsigned = upload('nrf_app', mcuboot_bytes(version: '1.4.0', signed: false))
    assert_includes unsigned.errors[:file], 'has no ECDSA P-256 signature'

    not_mcuboot = upload('nrf_app', 'plain bytes' * 10)
    assert_match(/not an MCUboot image/, not_mcuboot.errors[:file].first)

    wrong_version = upload('nrf_app', mcuboot_bytes(version: '1.3.9'))
    assert_match(/does not match the image header \(1\.3\.9\)/, wrong_version.errors[:version].first)

    truncated = upload('nrf_net', mcuboot_bytes(version: '1.4.0')[0, 60])
    refute truncated.persisted?

    assert upload('nrf_net', mcuboot_bytes(version: '1.4.0', build: 12), version: '1.4.0+12').persisted?
  end

  test 'images are capped at their slot size' do
    image = FirmwareImage.new(bundle: @bundle, component: 'stm32', version: '1.4.0', size: 2.megabytes, sha256: 'a' * 64,
                              signature_key_id: 'k')
    image.valid?
    assert image.errors.include?(:size)
  end

  test 'a saved image needs a stored file of its size' do
    image = FirmwareImage.new(bundle: @bundle, component: 'stm32', version: '1.4.0', size: 10, sha256: 'a' * 64,
                              signature_key_id: 'k')
    refute image.valid?
    assert image.errors.of_kind?(:file, 'must be uploaded')
  end

  test 'images of a published bundle cannot be added, changed or removed' do
    bundle = create_firmware_bundle(version: '2.0.0')
    image = bundle.images.first

    refute image.update(version: '2.0.1')
    refute image.update(signature_key_id: 'other')
    refute image.destroy
    assert FirmwareImage.exists?(image.id)

    added = Firmware::ImageUpload.call(bundle, temp_file(mcuboot_bytes(version: '2.0.0')).path,
                                       component: 'nrf_app', version: '2.0.0', signature_key_id: 'k')
    refute added.persisted?
    assert_match(/out of draft/, added.errors.full_messages.to_sentence)
    assert_equal 2, bundle.images.count
  end

  test 'a presigned download URL with its expiry' do
    bundle = create_firmware_bundle(version: '2.0.0')
    ActiveStorage::Current.host = 'http://example.com'
    url, expires_at = bundle.images.first.download_url
    assert url.present?
    assert_in_delta (Time.current + 1.hour).to_i, expires_at.to_i, 5
  ensure
    ActiveStorage::Current.reset
  end
end
