module Beeper
  module Marketplace
    # The marketplace's seed data (spec §1.5). Safe to run any number of times
    # (rake beeper:marketplace:seed, or db:seed through db/seeds/marketplace.rb):
    # - the marketplace taxon (Creators.config.marketplace_taxon_permalink, "marketplace"), the root
    #   of a "Marketplace" taxonomy unless a taxon with that permalink exists already, with the
    #   categories Sample Packs, Effects and Visualizers;
    # - the shipping category "Digital" (Creators.config.shipping_category_name);
    # - the Spree role "creator" (Creators.config.role_name);
    # - the free, claimable product "Beeper Starter Kit". It stays off sale (available_on nil)
    #   until rake beeper:marketplace:starter_kit[dir] publishes its files.
    module Seed
      CATEGORIES = ['Sample Packs', 'Effects', 'Visualizers'].freeze
      STARTER_KIT_SLUG = 'beeper-starter-kit'.freeze
      STARTER_KIT_NAME = 'Beeper Starter Kit'.freeze
      STARTER_KIT_DESCRIPTION = <<~TEXT.squish.freeze
        Sixteen one-shot drums, bass and stabs made for the Beeper Sampler. Free with a Beeper
        account: claim it once and it loads into the Sampler's pads, and stays on your device for
        offline use. It also comes built into the Beeper app.
      TEXT

      module_function

      def call
        Spree::Base.transaction do
          root = marketplace_taxon
          categories = CATEGORIES.map { |name| category(root, name) }
          shipping_category = Creators.shipping_category
          role = Creators.role
          kit = starter_kit(root, categories.first, shipping_category)
          { marketplace: root, categories: categories, shipping_category: shipping_category, role: role,
            starter_kit: kit }
        end
      end

      def marketplace_taxon
        permalink = Creators.config.marketplace_taxon_permalink.to_s.presence || 'marketplace'
        existing = Spree::Taxon.find_by(permalink: permalink)
        return existing if existing

        taxonomy = Spree::Taxonomy.find_or_create_by!(name: 'Marketplace')
        root = taxonomy.root
        root.update!(permalink: permalink) unless root.permalink == permalink
        root
      end

      def category(root, name)
        root.children.find_by(name: name) ||
          Spree::Taxon.create!(name: name, taxonomy_id: root.taxonomy_id, parent: root)
      end

      def starter_kit(root, sample_packs, shipping_category)
        product = Spree::Product.find_by(slug: STARTER_KIT_SLUG)
        unless product
          product = Spree::Product.new(name: STARTER_KIT_NAME, slug: STARTER_KIT_SLUG, price: 0, available_on: nil,
                                       description: STARTER_KIT_DESCRIPTION, shipping_category: shipping_category)
          store = Spree::Store.default
          product.stores << store if product.respond_to?(:stores) && store.persisted?
          product.save!
        end
        missing = [root, sample_packs].reject { |taxon| product.taxon_ids.include?(taxon.id) }
        product.taxons << missing if missing.any?
        claimable = DigitalAssets.config.claimable_property
        product.set_property(claimable, 'true') unless product.property(claimable) == 'true'
        product
      end
    end
  end
end
