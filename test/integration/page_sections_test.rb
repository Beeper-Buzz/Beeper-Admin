require 'test_helper'

# CMS sections are scoped to a storefront page by page_key. The homepage feed
# (no page_key) must stay exactly the homepage's sections.
class PageSectionsTest < ActionDispatch::IntegrationTest
  setup do
    @home = HomepageSection.create!(section_type: 'hero', title: 'Home hero')
    @creators_hero = HomepageSection.create!(section_type: 'hero', title: 'Creators hero', page_key: 'creators')
    @creators_faq = HomepageSection.create!(
      section_type: 'faq', page_key: 'creators',
      settings: '{"items": [{"question": "Q", "answer": "A"}]}'
    )
    @hidden = HomepageSection.create!(section_type: 'steps', page_key: 'creators', is_visible: false)
  end

  def sections(query = '')
    get "/api/v1/homepage_sections#{query}"
    assert_response :success
    JSON.parse(response.body)['response_data']['homepage_sections']
  end

  test 'without page_key the feed is the homepage only' do
    assert_equal [@home.id], sections.map { |s| s['id'] }
  end

  test 'page_key returns that page, visible, in order' do
    data = sections('?page_key=creators')
    assert_equal [@creators_hero.id, @creators_faq.id], data.map { |s| s['id'] }
    assert data.all? { |s| s['page_key'] == 'creators' }
  end

  test 'positions count per page' do
    assert_equal 1, @home.position
    assert_equal [1, 2, 3], [@creators_hero, @creators_faq, @hidden].map(&:position)
  end

  test 'settings posted as a JSON string are stored as an object' do
    data = sections('?page_key=creators').find { |s| s['id'] == @creators_faq.id }
    assert_equal({ 'items' => [{ 'question' => 'Q', 'answer' => 'A' }] }, data['settings'])
  end

  test 'invalid settings JSON and unknown pages are rejected' do
    bad = HomepageSection.new(section_type: 'faq', page_key: 'creators', settings: '{nope')
    refute bad.valid?
    assert bad.errors[:settings].any?

    refute HomepageSection.new(section_type: 'hero', page_key: 'nowhere').valid?
  end

  test 'moving a section only swaps within its page' do
    assert_nil @creators_hero.previous_on_page
    assert_equal @creators_faq, @creators_hero.next_on_page
    assert_nil @home.next_on_page
  end

  test 'the creators seed file holds only known section types' do
    seed = JSON.parse(File.read(Rails.root.join('db/cms/creators.json')))
    assert seed.any?
    seed.each { |s| assert_includes HomepageSection::SECTION_TYPES, s['section_type'] }
  end
end
