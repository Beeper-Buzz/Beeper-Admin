module Firmware
  # Deterministic staged rollout. A device's bucket for a bundle is
  #
  #   first 8 bytes of SHA-256("<device hash>:<bundle version>") as a big-endian integer, mod 100
  #
  # and it is in the rollout when bucket < rollout_percent. Raising the percentage only adds
  # devices; each bundle version shuffles devices afresh, so the same ones aren't always first.
  # Without a device hash (e.g. a recovery page that can't read it) only a 100 % bundle is offered.
  module Rollout
    module_function

    def bucket(device_hash, bundle_version)
      Digest::SHA256.digest("#{device_hash}:#{bundle_version}").unpack1('Q>') % 100
    end

    def eligible?(bundle, device_hash)
      percent = bundle.rollout_percent.to_i
      return true if percent >= 100
      return false if percent <= 0 || device_hash.blank?

      bucket(device_hash, bundle.version) < percent
    end
  end
end
