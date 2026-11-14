namespace :beeper do
  namespace :marketplace do
    desc 'Seed the marketplace: Marketplace taxons, Digital shipping category, creator role, Beeper Starter Kit product (idempotent)'
    task seed: :environment do
      result = Beeper::Marketplace::Seed.call
      puts "Marketplace seeded: taxon #{result[:marketplace].permalink} " \
           "(#{result[:categories].map(&:name).join(', ')}), shipping category #{result[:shipping_category].name}, " \
           "role #{result[:role].name}, product #{result[:starter_kit].slug}"
    end

    desc 'Publish the Beeper Starter Kit from a directory of WAVs plus manifest.json (pack_id "starter-kit"; idempotent)'
    task :starter_kit, [:dir] => :environment do |_task, args|
      dir = args[:dir].presence || ENV['DIR']
      abort 'Usage: rake "beeper:marketplace:starter_kit[path/to/kit]"' if dir.blank?

      begin
        result = Beeper::Marketplace::StarterKit.call(dir)
      rescue Beeper::Marketplace::StarterKit::Invalid => e
        abort e.message
      end
      asset = result[:asset]
      if result[:status] == :unchanged
        puts "Starter Kit unchanged (version #{asset.version}, #{asset.files.attachments.count} files)"
      else
        puts "Starter Kit version #{asset.version} published (#{asset.files.attachments.count} files, " \
             "#{asset.byte_size} bytes); #{result[:product].slug} is on sale and claimable"
      end
    end
  end
end
