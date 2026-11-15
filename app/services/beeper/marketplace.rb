module Beeper
  # Beeper's settings for the generic marketplace modules (digital assets, uploads, creators and
  # affiliates). config/initializers/beeper_marketplace.rb installs them in every environment but
  # test (see Beeper::DigitalKinds).
  #
  # ENV:
  #   AFFILIATE_LINK_BASE_URL  storefront base of affiliate links (default https://beeper.buzz)
  #   CREATORS_MARKETPLACE_TAXON  permalink of the marketplace taxon (default "marketplace", which
  #                               rake beeper:marketplace:seed creates)
  module Marketplace
    STOREFRONT_URL = 'https://beeper.buzz'.freeze
    LIBRARY_URL = "#{STOREFRONT_URL}/account/library".freeze

    module_function

    def install!
      Beeper::DigitalKinds.install!
      Uploads.configure { |config| apply_uploads(config) }
      apply_affiliates(Affiliates.config)
    end

    # Splits the generic json/glsl text rule: manifests stay at 256 KB, shaders get the visualizer
    # limit (64 KB, Beeper::Manifests::Visualizer), so an oversized shader is refused at upload.
    # Adds the glTF visualizer's scene: a .glb of at most 20 MB (visualizer-gltf.limits.json); its
    # poster is an image under the generic image rule (the manifest validator caps it at 2 MB).
    def apply_uploads(config)
      text = config.rules.delete(:text) || { content_types: [], extensions: [] }
      config.rules[:json] = { content_types: %w[application/json text/json text/plain], extensions: %w[json],
                              max_bytes: 256.kilobytes }
      config.rules[:shader] = { content_types: (text[:content_types] - %w[application/json text/json]) | %w[text/plain text/x-glsl application/octet-stream],
                                extensions: %w[glsl], max_bytes: Beeper::Manifests::Visualizer::MAX_SHADER_BYTES }
      config.rules[:scene] = { content_types: %w[model/gltf-binary application/octet-stream], extensions: %w[glb],
                               max_bytes: Beeper::Gltf::LIMITS['glbMaxBytes'] }
      config
    end

    def apply_affiliates(config)
      config.link_base_url = ENV['AFFILIATE_LINK_BASE_URL'].presence || STOREFRONT_URL
      config
    end

    # Whether an order holds anything the Beeper app downloads (a variant with a published asset).
    def digital_order?(order)
      order.line_items.any? { |item| item.variant&.digital? }
    end
  end
end
