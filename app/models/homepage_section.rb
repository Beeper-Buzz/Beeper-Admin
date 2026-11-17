class HomepageSection < Spree::Base
  # Storefront pages whose sections live here. `home` is the homepage feed;
  # every other key is a page the storefront renders from its own sections.
  PAGES = %w[home creators].freeze
  DEFAULT_PAGE = 'home'.freeze

  # Validations
  validates :section_type, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :page_key, inclusion: { in: PAGES }

  # Scopes
  scope :ordered, -> { order(position: :asc) }
  scope :visible, -> { where(is_visible: true) }
  scope :by_type, ->(type) { where(section_type: type) }
  scope :for_page, ->(key) { where(page_key: key.presence || DEFAULT_PAGE) }

  # Ransack searchable attributes
  self.whitelisted_ransackable_attributes = %w[title section_type page_key]
  self.whitelisted_ransackable_scopes = %w[search_homepage_sections]

  # Available section types
  SECTION_TYPES = %w[
    hero
    features
    products
    content
    testimonials
    gallery
    call_to_action
    newsletter
    video
    live_streams
    categories
    revenue_share
    steps
    faq
    custom
  ].freeze

  validates :section_type, inclusion: { in: SECTION_TYPES }

  # What each type reads from `settings`, shown under the admin's JSON field.
  SETTINGS_HELP = {
    'hero' => '{"button_text": "Apply to sell", "button_link": "/account/creator", "secondary_text": "See the marketplace", "secondary_link": "/browse?mode=marketplace"}',
    'features' => '{"items": [{"kind": "sample_pack", "title": "Sample packs", "body": "..."}]}',
    'products' => '{"source": "marketplace", "limit": 8, "link_text": "See the marketplace", "link": "/browse?mode=marketplace"}',
    'call_to_action' => '{"button_text": "Apply to sell", "button_link": "/account/creator", "note": "You need a Beeper account."}',
    'revenue_share' => '{"creator_share": 70, "example_price": 8, "slider_min": 0.5, "slider_max": 50}',
    'steps' => '{"items": [{"title": "Apply", "body": "..."}]}',
    'faq' => '{"items": [{"question": "...", "answer": "..."}]}'
  }.freeze

  # The admin form posts settings as a JSON string. Store it parsed so the API
  # serves an object rather than a string the storefront has to unpick; text
  # that isn't valid JSON is kept and rejected by validation below.
  def settings=(value)
    if value.is_a?(String)
      @settings_parse_error = nil
      if value.strip.empty?
        value = {}
      else
        begin
          value = JSON.parse(value)
        rescue JSON::ParserError => e
          @settings_parse_error = e.message
        end
      end
    end
    super(value)
  end

  validate :settings_must_be_json

  # Pretty JSON for the admin's settings textarea.
  def settings_json
    value = settings
    value = (JSON.parse(value) rescue value) if value.is_a?(String)
    value.is_a?(String) ? value : JSON.pretty_generate(value || {})
  end

  # Search scope
  def self.search_homepage_sections(query)
    if defined?(SpreeGlobalize)
      joins(:translations).order(:title).where(
        "LOWER(#{table_name}.title) LIKE LOWER(:query) OR LOWER(content) LIKE LOWER(:query)",
        query: "%#{query}%"
      ).distinct
    else
      where(
        "LOWER(#{table_name}.title) LIKE LOWER(:query) OR LOWER(content) LIKE LOWER(:query)",
        query: "%#{query}%"
      )
    end
  end

  # Set position before validation on create
  before_validation :set_position, on: :create

  # Class method to reset all positions sequentially
  def self.reset_positions!
    unscoped.order(:id).each_with_index do |section, index|
      section.update_column(:position, index + 1)
    end
  end

  # The section just before / after this one on the same page.
  def previous_on_page
    HomepageSection.for_page(page_key).where('position < ?', position).ordered.last
  end

  def next_on_page
    HomepageSection.for_page(page_key).where('position > ?', position).ordered.first
  end

  private

  def settings_must_be_json
    errors.add(:settings, "isn't valid JSON (#{@settings_parse_error})") if @settings_parse_error
  end

  def set_position
    if self.position.nil? || self.position.zero?
      self.position = (HomepageSection.for_page(page_key).maximum(:position) || 0) + 1
    end
  end
end
