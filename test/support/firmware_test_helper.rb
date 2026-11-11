# Shared helpers for the firmware module tests.
module FirmwareTestHelper
  DEVICE = ('ab' * 32).freeze

  # A minimal MCUboot image: header, payload, TLV area with a SHA-256 TLV and (when signed) an
  # ECDSA signature TLV. The signature bytes are dummies; the server only checks it is present.
  def mcuboot_bytes(version: '1.2.0', build: 0, signed: true, payload: 'radio-payload' * 8, magic: 0x96f3b83d)
    major, minor, revision = version.split(/[.+-]/).first(3).map(&:to_i)
    header = [magic, 0, 32, 0, payload.bytesize, 0, major, minor, revision, build, 0].pack('VVvvVVCCvVV')
    tlvs = [0x10, 32].pack('vv') + ("\x11" * 32)
    tlvs += [0x22, 72].pack('vv') + ("\x22" * 72) if signed
    header + payload + [0x6907, 4 + tlvs.bytesize].pack('vv') + tlvs
  end

  def image_bytes(component, version)
    if FirmwareImage::MCUBOOT_COMPONENTS.include?(component)
      mcuboot_bytes(version: version, payload: "#{component}-#{version}-" * 4)
    else
      "#{component}:#{version}:" * 16
    end
  end

  def temp_file(bytes)
    file = Tempfile.new(['firmware', '.bin'])
    file.binmode
    file.write(bytes)
    file.flush
    @firmware_temp_files = (@firmware_temp_files || []) << file
    file
  end

  def firmware_upload(bytes, name = 'image.bin')
    Rack::Test::UploadedFile.new(temp_file(bytes).path, 'application/octet-stream', true, original_filename: name)
  end

  def sha256_hex(bytes)
    Digest::SHA256.hexdigest(bytes)
  end

  # A bundle with images ({ component => version }), published unless state: 'draft'.
  def create_firmware_bundle(version:, images: { 'stm32' => version, 'stm32_assets' => version }, hw_rev: 'V114',
                             channel: 'stable', state: 'published', rollout_percent: 100, **attrs)
    bundle = FirmwareBundle.create!(hw_rev: hw_rev, version: version, channel: channel, state: 'draft',
                                    rollout_percent: rollout_percent, **attrs)
    images.each do |component, image_version|
      bytes = image_bytes(component, image_version)
      image = Firmware::ImageUpload.call(bundle, temp_file(bytes).path,
                                         component: component, version: image_version, signature_key_id: 'dev-1')
      raise "image did not save: #{image.errors.full_messages.to_sentence}" unless image.persisted?
    end
    bundle.reload
    unless state == 'draft'
      bundle.publish! || raise(bundle.errors.full_messages.to_sentence)
      bundle.update!(state: state) unless state == 'published'
    end
    bundle
  end

  # A device hash whose rollout bucket for `version` is (or isn't) below `percent`.
  def device_in_rollout(version, percent, inside: true)
    (0..10_000).each do |i|
      hash = Digest::SHA256.hexdigest("device-#{i}")
      return hash if (Firmware::Rollout.bucket(hash, version) < percent) == inside
    end
    raise 'no device found'
  end
end

ActiveSupport::TestCase.include(FirmwareTestHelper)
