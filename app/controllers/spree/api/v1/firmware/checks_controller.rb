module Spree
  module Api
    module V1
      module Firmware
        # GET /api/v1/firmware/check?hw=V114&channel=stable&device=<hash>&app_version=2.7.0
        #     &stm32=1.4.0&stm32_assets=1.4.0&nrf_app=1.2.0&nrf_net=1.2.0
        #
        #     &security_epoch=2   (optional; or per component: stm32_epoch, nrf_app_epoch, ...)
        #
        # No auth (devices of signed-out users update too). Rate-limited per device when device is
        # sent (with a loose per-IP ceiling for shared carrier NAT addresses), else strictly per IP.
        # hw is required; channel is stable, beta or internal (default stable); device is the
        # device's hashed id (64 hex; without it only 100 % rollouts are offered); a missing
        # component version means "unknown", so that image is offered. The highest reported epoch
        # is a floor: no bundle of a lower security_epoch is offered. See ::Firmware::Offer for how
        # the bundle is chosen.
        #
        # 200 {
        #   bundle: null | { id, hw, version, channel, security_epoch, min_app_version, notes,
        #                    published_at, images: [{ component, version, size, sha256,
        #                    signature_key_id, link_proto, app_proto, content_hash, url,
        #                    url_expires_at }] },          # images in install order
        #   app_update_required: bool, min_app_version: "x.y.z" | null,  # a newer bundle needs a newer app
        #   revoked: null | { version, notes }             # the device runs a revoked bundle
        # }
        # 422 { error, fields }; 429 { error }.
        class ChecksController < ActionController::API
          include ::Firmware::ApiResponses

          EPOCH_FORMAT = /\A\d{1,9}\z/.freeze

          def show
            query = check_params
            return if performed?
            return render_error('Too many requests. Try again later.', :too_many_requests) if rate_limited?(rate_keys(query[:device_hash]))

            ActiveStorage::Current.host = request.base_url
            response.headers['Cache-Control'] = 'no-store'
            render json: present(::Firmware::Offer.new(**query).call)
          end

          private

          # With a device hash: per device, plus a loose per-IP ceiling (many phones share one
          # carrier NAT address). Without one: the strict per-IP limit.
          def rate_keys(device_hash)
            ip = ::Firmware::RateLimit.ip_key(request.remote_ip)
            device_hash ? { check_device: device_hash, check_ip_shared: ip } : { check_ip: ip }
          end

          # The highest of security_epoch and <component>_epoch, as an Integer, or nil when none was
          # sent. Records a field error for a value that isn't a small non-negative integer.
          def reported_epoch(errors)
            names = [:security_epoch] + ::Firmware::COMPONENTS.map { |component| :"#{component}_epoch" }
            epochs = names.filter_map do |name|
              value = string_param(name)
              next unless value
              next value.to_i if EPOCH_FORMAT.match?(value)

              errors[name] = ['must be a non-negative integer']
              nil
            end
            epochs.max
          end

          def check_params
            errors = {}
            hw = string_param(:hw)
            errors[:hw] = ['is required'] if hw.nil?
            errors[:hw] = ['is not a hardware revision'] if hw && !::Firmware::HW_REV_FORMAT.match?(hw)
            channel = (string_param(:channel) || 'stable').downcase
            errors[:channel] = ["must be one of #{::Firmware::CHANNELS.join(', ')}"] unless ::Firmware::CHANNELS.include?(channel)
            device = string_param(:device)&.downcase
            errors[:device] = ['must be a SHA-256 hex digest'] if device && !::Firmware::DEVICE_HASH_FORMAT.match?(device)
            app_version = string_param(:app_version)
            errors[:app_version] = ['is too long'] if app_version.to_s.length > VERSION_PARAM_MAX
            current = ::Firmware::COMPONENTS.each_with_object({}) do |component, map|
              value = string_param(component)
              next unless value

              errors[component.to_sym] = ['is too long'] if value.length > VERSION_PARAM_MAX
              map[component] = value
            end
            epoch = reported_epoch(errors)
            if errors.any?
              field, messages = errors.first
              return render_error("#{field} #{messages.first}", :unprocessable_entity, fields: errors)
            end

            { hw_rev: hw, channel: channel, device_hash: device, app_version: app_version, current_versions: current,
              security_epoch: epoch }
          end

          def present(offer)
            {
              bundle: offer.bundle && present_bundle(offer.bundle, offer.images),
              app_update_required: offer.app_update_required,
              min_app_version: offer.required_app_version,
              revoked: offer.revoked_bundle && { version: offer.revoked_bundle.version, notes: offer.revoked_bundle.release_notes }
            }
          end

          def present_bundle(bundle, images)
            {
              id: bundle.id,
              hw: bundle.hw_rev,
              version: bundle.version,
              channel: bundle.channel,
              security_epoch: bundle.security_epoch,
              min_app_version: bundle.min_app_version,
              notes: bundle.release_notes,
              published_at: bundle.published_at&.iso8601,
              images: images.map { |image| present_image(image) }
            }
          end

          def present_image(image)
            url, expires_at = image.download_url
            {
              component: image.component,
              version: image.version,
              size: image.size,
              sha256: image.sha256,
              signature_key_id: image.signature_key_id,
              link_proto: image.link_proto,
              app_proto: image.app_proto,
              content_hash: image.content_hash,
              url: url,
              url_expires_at: expires_at.iso8601
            }
          end
        end
      end
    end
  end
end
