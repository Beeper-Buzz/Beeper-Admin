require "test_helper"

class CommunityGuidelinesSeedTest < ActiveSupport::TestCase
  SEED = Rails.root.join("db/seeds/011_community_guidelines.rb")

  def pages
    ActiveRecord::Base.connection.select_all("SELECT title, body FROM spree_pages WHERE slug = 'community-guidelines'").to_a
  end

  test "creates the page once and never overwrites it" do
    load SEED
    assert_equal 1, pages.size
    assert_includes pages.first["body"], "We review reports within 24 hours"

    ActiveRecord::Base.connection.update("UPDATE spree_pages SET body = 'edited' WHERE slug = 'community-guidelines'")
    load SEED
    assert_equal 1, pages.size
    assert_equal "edited", pages.first["body"]
  end
end
