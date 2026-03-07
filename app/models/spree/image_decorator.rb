module Spree
    module ImageDecorator
        module ClassMethods
            def styles
                {
                    mini: '48x48>',
                    small: '100x100>',
                    product: '240x240>',
                    large: '600x600>',
                    xl: '1000x1000>',
                    widescreen: '1600x900>',
                    portrait: '900x1600>'
                }
            end
        end

        # Override instance methods to remove extent + background (letterboxing)
        # Images keep natural aspect ratio; frontend uses object-cover to fill containers.

        def styles
            self.class.styles.map do |_, size|
                width, height = size.chop.split('x')
                {
                    url: polymorphic_path(attachment.variant(
                        resize: size,
                        gravity: 'center',
                        quality: 80
                    ), only_path: true),
                    width: width,
                    height: height
                }
            end
        end

        def style(name)
            size = self.class.styles[name]
            return unless size

            width, height = size.chop.split('x')
            {
                url: polymorphic_path(attachment.variant(
                    resize: size,
                    gravity: 'center',
                    quality: 80
                ), only_path: true),
                size: size,
                width: width,
                height: height
            }
        end

        def plp_url
            size = self.class.styles[:plp_and_carousel] || self.class.styles[:large]
            variant = attachment.variant(
                resize: size,
                gravity: 'center',
                quality: 80
            )
            polymorphic_path(variant, only_path: true)
        end

        def self.prepended(base)
            base.singleton_class.prepend ClassMethods
        end
    end

    Spree::Image.prepend(Spree::ImageDecorator)
end
