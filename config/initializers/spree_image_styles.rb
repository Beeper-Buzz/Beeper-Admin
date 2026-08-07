# Extend Spree image styles with xlarge for hi-res PDP display.
# Existing images need: rake paperclip:refresh:thumbnails class=Spree::Image
Rails.application.config.to_prepare do
  Spree::Image.attachment_definitions[:attachment][:styles][:xlarge] = '2400x2400>'
end
