module Spree
  module Api
    module V1
      module Firmware
        # POST /api/v1/admin/firmware/bundles (multipart), for CI: creates a DRAFT bundle with its
        # images. Publishing stays an admin action.
        #
        # Auth: `Authorization: Bearer <FIRMWARE_UPLOAD_TOKEN>`. The token can only create drafts:
        # it can't publish, change or delete anything, and isn't a user's credential.
        #
        # Fields: hw, version, channel (default internal), min_app_version, security_epoch
        # (default 0), release_notes, and per component (stm32, stm32_assets, nrf_app, nrf_net):
        #   images[<component>][file]              the signed image
        #   images[<component>][version]
        #   images[<component>][sha256]            required: checked against the bytes received
        #   images[<component>][signature_key_id]
        #   images[<component>][size], [link_proto], [app_proto], [content_hash]   optional
        #
        # 201 { id, hw, version, channel, state, images: [{ component, version, size, sha256 }], admin_path }
        # 401 { error }; 409 { error } when the version exists for that hw and channel;
        # 422 { error, fields } (image errors under "<component>.<field>"). All or nothing.
        class UploadsController < ActionController::API
          include ::Firmware::ApiResponses

          BUNDLE_FIELDS = %i[version channel min_app_version release_notes].freeze
          IMAGE_FIELDS = %i[version sha256 size signature_key_id link_proto app_proto content_hash].freeze

          before_action :authenticate_ci

          def create
            bundle = FirmwareBundle.new(bundle_attributes)
            return render_record_errors(bundle, 'Bundle is invalid') unless bundle.valid? || conflict?(bundle)
            return render_error('This version already exists for that hardware and channel', :conflict) if conflict?(bundle)

            uploads = image_uploads
            return if performed?

            failed = save_all(bundle, uploads)
            return render_error("#{failed.component} #{failed.errors.full_messages.first}", :unprocessable_entity, fields: image_fields(failed)) if failed

            render json: present(bundle.reload), status: :created
          end

          private

          def authenticate_ci
            token = request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
            return if ::Firmware.config.valid_upload_token?(token)

            Rails.logger.warn('[firmware] upload refused: FIRMWARE_UPLOAD_TOKEN is not set') if ::Firmware.config.upload_tokens.empty?
            render_error('unauthorized', :unauthorized)
          end

          def bundle_attributes
            attrs = BUNDLE_FIELDS.index_with { |field| string_param(field) }.compact
            attrs[:hw_rev] = string_param(:hw)
            attrs[:channel] ||= 'internal'
            attrs[:security_epoch] = string_param(:security_epoch) || 0
            attrs[:state] = 'draft'
            attrs[:rollout_percent] = 0
            attrs[:created_by] = 'ci'
            attrs
          end

          def conflict?(bundle)
            bundle.errors.of_kind?(:version, :taken)
          end

          # [[component, attributes, path]] or nil after rendering a 422.
          def image_uploads
            raw = params[:images]
            raw = raw.to_unsafe_h if raw.is_a?(ActionController::Parameters)
            unless raw.is_a?(Hash) && raw.any?
              return render_error('images is required', :unprocessable_entity, fields: { images: ['at least one image is required'] })
            end

            unknown = raw.keys.map(&:to_s) - ::Firmware::COMPONENTS
            if unknown.any?
              return render_error("unknown components: #{unknown.join(', ')}", :unprocessable_entity, fields: { images: ["unknown components: #{unknown.join(', ')}"] })
            end

            raw.map do |component, fields|
              fields = {} unless fields.is_a?(Hash)
              file = fields['file'] || fields[:file]
              unless file.respond_to?(:tempfile) || file.respond_to?(:path)
                return render_error("#{component} file is required", :unprocessable_entity, fields: { "#{component}.file" => ['is required'] })
              end
              attrs = IMAGE_FIELDS.index_with { |field| string_param(field.to_s, fields) }.compact
              if attrs[:sha256].blank?
                return render_error("#{component} sha256 is required", :unprocessable_entity, fields: { "#{component}.sha256" => ['is required'] })
              end

              [component.to_s, attrs.merge(component: component.to_s), file.respond_to?(:tempfile) ? file.tempfile.path : file.path]
            end
          end

          # Saves the bundle and every image in one transaction; returns the first image that
          # failed (nothing is kept then), or nil.
          def save_all(bundle, uploads)
            stored_keys = []
            failed = nil
            FirmwareBundle.transaction do
              bundle.save!
              uploads.sort_by { |component, _, _| ::Firmware::COMPONENTS.index(component) }.each do |_, attrs, path|
                image = ::Firmware::ImageUpload.call(bundle, path, attrs)
                if image.persisted?
                  stored_keys << image.file.blob.key
                else
                  failed = image
                  raise ActiveRecord::Rollback
                end
              end
            end
            stored_keys.each { |key| ::Firmware::ImageUpload.discard(key) } if failed
            failed
          end

          def image_fields(image)
            image.errors.to_hash.transform_keys { |field| "#{image.component}.#{field}" }
          end

          def present(bundle)
            {
              id: bundle.id,
              hw: bundle.hw_rev,
              version: bundle.version,
              channel: bundle.channel,
              state: bundle.state,
              images: bundle.images.map { |i| { component: i.component, version: i.version, size: i.size, sha256: i.sha256 } },
              admin_path: Spree::Core::Engine.routes.url_helpers.admin_firmware_bundle_path(bundle)
            }
          end
        end
      end
    end
  end
end
