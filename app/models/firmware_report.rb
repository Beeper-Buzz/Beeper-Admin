# The result of one install attempt, sent by a client (app or recovery page) for every terminal
# outcome. Devices are identified only by the hashed id they report (Firmware::DEVICE_HASH_FORMAT).
# Write-only from clients; read in the admin's bundle page.
class FirmwareReport < ApplicationRecord
  RESULTS = %w[ok failed rolled_back aborted].freeze
  PLATFORMS = %w[ios android web].freeze
  SHORT_FIELDS = %i[from_version to_version stage error_code app_version phone_model].freeze
  SHORT_MAX = 64
  PHONE_MODEL_MAX = 128

  belongs_to :bundle, class_name: 'FirmwareBundle', foreign_key: :firmware_bundle_id, inverse_of: :reports
  belongs_to :user, class_name: 'Spree::User', optional: true

  before_validation :normalize
  validates :device_hash, format: { with: Firmware::DEVICE_HASH_FORMAT, message: 'must be a lowercase SHA-256 hex digest' }
  validates :result, inclusion: { in: RESULTS }
  validates :component, inclusion: { in: Firmware::COMPONENTS }, allow_nil: true
  validates :platform, inclusion: { in: PLATFORMS }, allow_nil: true
  validates :duration_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 2**31 }, allow_nil: true
  validates(*(SHORT_FIELDS - [:phone_model]), length: { maximum: SHORT_MAX })
  validates :phone_model, length: { maximum: PHONE_MODEL_MAX }
  validate :text_without_null_bytes

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  private

  def normalize
    self.device_hash = device_hash.to_s.strip.downcase.presence
    self.result = result.to_s.strip.downcase.presence
    self.component = component.to_s.strip.downcase.presence
    self.platform = platform.to_s.strip.downcase.presence
    SHORT_FIELDS.each { |field| self[field] = self[field].to_s.strip.presence }
  end

  def text_without_null_bytes
    SHORT_FIELDS.each do |field|
      value = self[field]
      errors.add(field, 'contains invalid characters') if value.is_a?(String) && value.include?("\0")
    end
  end
end
