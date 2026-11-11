# One firmware release for one hardware revision: a tested set of signed images (at most one per
# component), on a channel, with a staged rollout. See app/services/firmware.rb.
#
# States: draft (editable, never offered) -> published (offered by `check`) <-> paused (kill
# switch: offered to no one, devices keep what they have) -> revoked (offered to no one, and
# devices still running it are told so; `check` offers them the newest good bundle).
# Once out of draft, the hardware revision, version, security epoch and images never change.
class FirmwareBundle < ApplicationRecord
  STATES = %w[draft published paused revoked].freeze
  FROZEN_AFTER_DRAFT = %w[hw_rev version security_epoch].freeze
  NOTES_MAX = 10_000

  has_many :images, -> { order(:id) }, class_name: 'FirmwareImage', inverse_of: :bundle, dependent: :destroy
  has_many :reports, class_name: 'FirmwareReport', inverse_of: :bundle, dependent: :delete_all

  before_validation :normalize
  validates :hw_rev, presence: true, format: { with: Firmware::HW_REV_FORMAT, allow_blank: true }
  validates :version, presence: true
  validate :version_is_semver
  validates :version, uniqueness: { scope: %i[hw_rev channel], message: 'already exists for this hardware and channel' }
  validates :channel, inclusion: { in: Firmware::CHANNELS }
  validates :state, inclusion: { in: STATES }
  validates :rollout_percent, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :security_epoch, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :release_notes, length: { maximum: NOTES_MAX }
  validates :created_by, length: { maximum: 255 }
  validate :min_app_version_is_semver
  validate :frozen_fields_unchanged, on: :update
  validate :publishable, if: -> { state == 'published' && state_changed? }

  before_destroy :only_drafts_are_deleted, prepend: true

  scope :for_hw, ->(hw_rev) { where(hw_rev: hw_rev) }

  STATES.each do |name|
    define_method("#{name}?") { state == name }
  end

  # Newest version first (semver order), ties by newest row.
  def self.sort_newest_first(bundles)
    bundles.sort do |a, b|
      cmp = Firmware::Semver.compare(b.version, a.version) || 0
      cmp.zero? ? b.id.to_i <=> a.id.to_i : cmp
    end
  end

  # True when the client reported at least one of this bundle's components and every reported
  # one matches: the device runs this bundle (a recovery page that sees only the main MCU still
  # matches on that).
  def installed_on?(current_versions)
    reported = images.select { |image| current_versions[image.component].present? }
    reported.any? && reported.all? { |image| current_versions[image.component] == image.version }
  end

  # The images a device on `current_versions` needs, in install order: those whose version
  # differs from (or is missing in) the report, plus the partner of a paired component.
  def images_to_install(current_versions)
    needed = images.reject { |image| current_versions[image.component] == image.version }
    if (needed.map(&:component) & Firmware::PAIRED_COMPONENTS).any?
      needed |= images.select { |image| Firmware::PAIRED_COMPONENTS.include?(image.component) }
    end
    needed.sort_by { |image| Firmware::COMPONENTS.index(image.component) }
  end

  def requires_newer_app?(app_version)
    return false if min_app_version.blank? || app_version.blank?
    return true unless Gem::Version.correct?(app_version.to_s.strip)

    Gem::Version.new(app_version.to_s.strip) < Firmware::Semver.parse(min_app_version)
  end

  def editable?
    draft?
  end

  # State changes. Each returns true, or false with errors on the record.
  def publish!
    return transition_error('only a draft or paused bundle can be published') unless draft? || paused?

    previous = [state, published_at]
    self.state = 'published'
    self.published_at ||= Time.current
    return true if save

    self.state, self.published_at = previous
    false
  end

  def pause!
    return transition_error('only a published bundle can be paused') unless published?

    change_state('paused')
  end

  def revoke!
    return transition_error('only a published or paused bundle can be revoked') unless published? || paused?

    change_state('revoked')
  end

  def label
    "#{hw_rev} #{version} (#{channel})"
  end

  private

  def normalize
    self.hw_rev = hw_rev.to_s.strip.presence
    self.version = version.to_s.strip.presence
    self.channel = channel.to_s.strip.downcase.presence
    self.min_app_version = min_app_version.to_s.strip.presence
    self.release_notes = release_notes.to_s.strip.presence
  end

  def version_is_semver
    return if version.blank? || Firmware::Semver.valid?(version)

    errors.add(:version, 'must be a semantic version (e.g. 1.4.0)')
  end

  def min_app_version_is_semver
    return if min_app_version.blank? || Firmware::Semver.valid?(min_app_version)

    errors.add(:min_app_version, 'must be a semantic version (e.g. 2.7.0)')
  end

  def frozen_fields_unchanged
    return if state_was == 'draft'

    FROZEN_AFTER_DRAFT.each do |field|
      errors.add(field, "can't change once the bundle is out of draft") if will_save_change_to_attribute?(field)
    end
  end

  def publishable
    list = images.to_a
    return errors.add(:base, 'A bundle needs at least one image to be published') if list.empty?

    missing = list.reject { |image| image.file.attached? }.map(&:component)
    errors.add(:base, "Images without a file: #{missing.join(', ')}") if missing.any?

    paired = list.map(&:component) & Firmware::PAIRED_COMPONENTS
    return if paired.empty? || paired.size == Firmware::PAIRED_COMPONENTS.size

    errors.add(:base, "#{Firmware::PAIRED_COMPONENTS.join(' and ')} ship together; add the missing one")
  end

  # Writes only the state, skipping validations, so nothing else on the record (an edit in
  # progress, a rule added after it was published) can block the kill switch.
  def change_state(new_state)
    update_columns(state: new_state, updated_at: Time.current)
    true
  end

  def transition_error(message)
    errors.add(:state, message)
    false
  end

  def only_drafts_are_deleted
    return if draft?

    errors.add(:base, 'Only a draft can be deleted; pause or revoke a released bundle instead')
    throw :abort
  end
end
