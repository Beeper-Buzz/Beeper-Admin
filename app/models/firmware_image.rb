# One signed image of a FirmwareBundle. The signature is inside the file (the MCUboot TLV trailer
# for the radio cores, the image header for the main MCU and its assets), so the server holds no
# keys; the device verifies before installing. `sha256` and `size` are checked against the bytes
# when the file is uploaded (Firmware::ImageUpload) and the stored blob's size on every save.
# Images only change while their bundle is a draft.
class FirmwareImage < ApplicationRecord
  SHA256_FORMAT = /\A[0-9a-f]{64}\z/.freeze
  KEY_ID_FORMAT = /\A[A-Za-z0-9_.:-]{1,64}\z/.freeze
  CONTENT_HASH_FORMAT = /\A[0-9a-f]{8,128}\z/.freeze
  MCUBOOT_COMPONENTS = %w[nrf_app nrf_net].freeze

  belongs_to :bundle, class_name: 'FirmwareBundle', foreign_key: :firmware_bundle_id, inverse_of: :images
  has_one_attached :file

  before_validation :normalize
  validates :component, inclusion: { in: Firmware::COMPONENTS }
  validates :component, uniqueness: { scope: :firmware_bundle_id, message: 'is already in this bundle' }
  validates :version, presence: true
  validate :version_is_semver
  validates :size, numericality: { only_integer: true, greater_than: 0 }
  validate :size_within_slot
  validates :sha256, format: { with: SHA256_FORMAT, message: 'must be 64 hex characters' }
  validates :signature_key_id, presence: true
  validates :signature_key_id, format: { with: KEY_ID_FORMAT, allow_blank: true }
  validates :link_proto, :app_proto, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :content_hash, format: { with: CONTENT_HASH_FORMAT, message: 'must be 8-128 hex characters' }, allow_nil: true
  validate :bundle_is_draft
  validate :staged_file_matches
  validate :file_present_and_sized

  before_destroy :only_while_draft, prepend: true

  attr_reader :staged_path

  # Points the image at a local file about to be uploaded: measures and hashes it, fills size and
  # sha256 when they weren't declared, and remembers the result for validation (a declared value
  # that differs from the bytes is an error).
  def stage_file(path)
    @staged_path = path.to_s
    @staged_size = File.size(@staged_path)
    @staged_sha256 = Digest::SHA256.file(@staged_path).hexdigest
    self.size = @staged_size if size.blank?
    self.sha256 = @staged_sha256 if sha256.blank?
    self
  end

  def download_filename
    "#{bundle&.hw_rev}-#{component}-#{version}.bin"
  end

  # A presigned GET URL for the file and when it stops working.
  def download_url(expires_in: Firmware.config.url_expires_in)
    [file.blob.url(expires_in: expires_in, disposition: :attachment, filename: download_filename),
     Time.current + expires_in]
  end

  private

  def normalize
    self.component = component.to_s.strip.downcase.presence
    self.version = version.to_s.strip.presence
    self.sha256 = sha256.to_s.strip.downcase.presence
    self.signature_key_id = signature_key_id.to_s.strip.presence
    self.content_hash = content_hash.to_s.strip.downcase.presence
  end

  def version_is_semver
    return if version.blank? || Firmware::Semver.valid?(version)

    errors.add(:version, 'must be a semantic version (e.g. 1.4.0)')
  end

  def size_within_slot
    max = Firmware::MAX_IMAGE_BYTES[component]
    return unless max && size.to_i > max

    errors.add(:size, "must be at most #{max / 1.megabyte} MB for #{component}")
  end

  def bundle_is_draft
    return if bundle.nil? || bundle.draft?
    return unless new_record? || changed? || attachment_changes.key?('file')

    errors.add(:base, "Images can't change once the bundle is out of draft")
  end

  def staged_file_matches
    return unless @staged_path

    if size.to_i != @staged_size
      errors.add(:size, "does not match the uploaded file (#{@staged_size} bytes)")
    end
    errors.add(:sha256, 'does not match the uploaded file') if sha256 != @staged_sha256
    check_mcuboot_file if MCUBOOT_COMPONENTS.include?(component)
  end

  # Radio images must be signed MCUboot images of the declared version.
  def check_mcuboot_file
    image = Firmware::McubootImage.read(@staged_path)
    return errors.add(:file, image.error) unless image.valid?
    return errors.add(:file, 'has no ECDSA P-256 signature') unless image.ecdsa_signed?

    declared = Firmware::Semver.parse(version)
    return unless declared && declared.release.to_s != Gem::Version.new(image.version).to_s

    errors.add(:version, "does not match the image header (#{image.version})")
  end

  def file_present_and_sized
    return if @staged_path # uploaded and attached after validation (Firmware::ImageUpload)
    return errors.add(:file, 'must be uploaded') unless file.attached?
    return if file.blob.byte_size == size.to_i

    errors.add(:size, "does not match the stored file (#{file.blob.byte_size} bytes)")
  end

  def only_while_draft
    return if bundle.nil? || bundle.draft? || destroyed_by_association

    errors.add(:base, "Images can't change once the bundle is out of draft")
    throw :abort
  end
end
