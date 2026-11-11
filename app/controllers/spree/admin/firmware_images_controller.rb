module Spree
  module Admin
    # Upload or remove one image of a draft firmware bundle (Firmware::ImageUpload checks the
    # file against the declared sha256 and size, and radio images for an MCUboot signature).
    class FirmwareImagesController < Spree::Admin::BaseController
      before_action :load_bundle

      def create
        upload = params.dig(:firmware_image, :file)
        unless upload.respond_to?(:tempfile)
          flash[:error] = 'Choose an image file'
          return redirect_to spree.admin_firmware_bundle_path(@bundle)
        end

        image = Firmware::ImageUpload.call(@bundle, upload.tempfile.path, image_params)
        if image.persisted?
          flash[:success] = "#{image.component} #{image.version} added"
        else
          flash[:error] = image.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_firmware_bundle_path(@bundle)
      end

      def destroy
        image = @bundle.images.find(params[:id])
        if image.destroy
          flash[:success] = "#{image.component} removed"
        else
          flash[:error] = image.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_firmware_bundle_path(@bundle)
      end

      private

      def model_class
        FirmwareBundle
      end

      def load_bundle
        @bundle = FirmwareBundle.find(params[:firmware_bundle_id])
      end

      def image_params
        attrs = params.require(:firmware_image).permit(:component, :version, :sha256, :signature_key_id, :link_proto,
                                                       :app_proto, :content_hash).to_h
        attrs.transform_values { |v| v.is_a?(String) ? v.strip.presence : v }.compact
      end
    end
  end
end
