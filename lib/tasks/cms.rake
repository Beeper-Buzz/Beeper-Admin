namespace :beeper do
  namespace :cms do
    desc "Seed a storefront page's CMS sections from db/cms/<page>.json (default creators). " \
         'Skips a page that already has sections unless FORCE=1, which replaces them.'
    task :seed_page, [:page] => :environment do |_task, args|
      page = args[:page].presence || ENV['PAGE'].presence || 'creators'
      abort "Unknown page #{page.inspect} (#{HomepageSection::PAGES.join(', ')})" unless HomepageSection::PAGES.include?(page)

      path = Rails.root.join('db/cms', "#{page}.json")
      abort "No #{path}" unless File.exist?(path)

      existing = HomepageSection.for_page(page)
      if existing.exists? && ENV['FORCE'] != '1'
        puts "#{page}: #{existing.count} sections already, left alone (FORCE=1 replaces them)"
        next
      end

      sections = JSON.parse(File.read(path))
      HomepageSection.transaction do
        existing.destroy_all
        sections.each_with_index do |attrs, index|
          HomepageSection.create!(
            page_key: page,
            position: index + 1,
            is_visible: true,
            section_type: attrs.fetch('section_type'),
            title: attrs['title'],
            content: attrs['content'],
            settings: attrs['settings'] || {}
          )
        end
      end
      puts "#{page}: #{sections.size} sections seeded"
    end
  end
end
