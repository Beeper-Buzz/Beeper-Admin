module Firmware
  # What `GET /api/v1/firmware/check` offers one device.
  #
  # 1. The device's current bundle is the newest released (not draft, not revoked) bundle for its
  #    hardware whose images match the versions it reported (FirmwareBundle#installed_on?), on any
  #    channel. Only bundles newer than it (and not of a lower security epoch) are candidates, so
  #    lowering a rollout or leaving the beta channel never downgrades a device. A device on a
  #    revoked bundle has no current bundle and is offered the newest good one, even if older.
  # 2. Candidates: published bundles for the hardware on the channels the client's channel sees
  #    (Firmware::CHANNEL_AUDIENCE), newest first.
  # 3. The first candidate whose rollout includes the device (Firmware::Rollout) wins, unless it
  #    needs a newer app: then app_update_required is set and the next candidate is tried.
  # 4. The offer lists only the images to install (FirmwareBundle#images_to_install), in install
  #    order; none means the device is up to date (bundle nil).
  class Offer
    Result = Struct.new(:bundle, :images, :app_update_required, :required_app_version, :revoked_bundle,
                        keyword_init: true)

    def initialize(hw_rev:, channel:, device_hash: nil, app_version: nil, current_versions: {})
      @hw_rev = hw_rev
      @channel = channel
      @device_hash = device_hash
      @app_version = app_version
      @current = current_versions.to_h.transform_keys(&:to_s)
    end

    def call
      bundles = FirmwareBundle.sort_newest_first(released_bundles)
      current = bundles.find { |b| !b.revoked? && b.installed_on?(@current) }
      revoked = bundles.find { |b| b.revoked? && b.installed_on?(@current) }
      required_app = nil

      candidates(bundles, current).each do |bundle|
        next unless Firmware::Rollout.eligible?(bundle, @device_hash)

        if bundle.requires_newer_app?(@app_version)
          required_app ||= bundle.min_app_version
          next
        end

        images = bundle.images_to_install(@current)
        return result(images.any? ? bundle : nil, images, required_app, revoked)
      end
      result(nil, [], required_app, revoked)
    end

    private

    def released_bundles
      FirmwareBundle.for_hw(@hw_rev).where.not(state: 'draft').includes(images: { file_attachment: :blob }).to_a
    end

    def candidates(bundles, current)
      audience = Firmware::CHANNEL_AUDIENCE.fetch(@channel)
      bundles.select do |bundle|
        next false unless bundle.published? && audience.include?(bundle.channel)
        next true unless current

        Firmware::Semver.compare(bundle.version, current.version) == 1 && bundle.security_epoch >= current.security_epoch
      end
    end

    def result(bundle, images, required_app, revoked)
      Result.new(bundle: bundle, images: images, app_update_required: required_app.present?,
                 required_app_version: required_app, revoked_bundle: revoked)
    end
  end
end
