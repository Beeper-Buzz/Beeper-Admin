# Community guidelines page (linked from the app when a profile is made public). Created only
# when no page has this slug, so edits made in the admin are never overwritten.
# Run on an existing database with: bin/rails runner 'load "db/seeds/011_community_guidelines.rb"'
community_pages = Class.new(ActiveRecord::Base) { self.table_name = 'spree_pages' }

unless community_pages.where(slug: ['community-guidelines', '/community-guidelines']).exists?
  community_pages.create!(
    title: 'Community guidelines',
    slug: 'community-guidelines',
    body: "Beeper is for making and sharing music. Don't post anything hateful, harassing, sexual, " \
          "violent or illegal, don't impersonate anyone, and don't spam. We review reports within 24 " \
          "hours and remove content or accounts that break these rules. Report a profile from its … " \
          "menu, or email support.",
    meta_title: 'Community guidelines',
    meta_description: 'What is and is not allowed on Beeper.',
    visible: true,
    show_in_header: false,
    show_in_footer: true,
    show_in_sidebar: false,
    position: 99
  )
end
