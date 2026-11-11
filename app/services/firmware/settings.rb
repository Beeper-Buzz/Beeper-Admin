module Firmware
  # Firmware.config. Reads ENV unless a value was set (tests set them directly).
  #
  # ENV:
  #   FIRMWARE_UPLOAD_TOKEN      token(s) CI sends to create draft bundles, comma-separated so a
  #                              new one can be added before the old one is removed. Unset: the
  #                              upload endpoint refuses everything.
  #   FIRMWARE_ALLOWED_ORIGINS   browser origins allowed to call check and reports (read by
  #                              config/initializers/cors.rb)
  class Settings
    attr_writer :upload_tokens
    attr_accessor :rate_limits, :url_expires_in

    def initialize
      # Presigned download URLs; a download that outlives one asks `check` again.
      @url_expires_in = 1.hour
      # Fixed windows, see Firmware::RateLimit.
      @rate_limits = {
        check_ip: { limit: 240, window: 1.hour },
        report_ip: { limit: 120, window: 1.hour },
        report_device: { limit: 100, window: 24.hours }
      }
    end

    def upload_tokens
      raw = defined?(@upload_tokens) ? @upload_tokens : ENV['FIRMWARE_UPLOAD_TOKEN']
      Array(raw.is_a?(String) ? raw.split(',') : raw).map { |t| t.to_s.strip }.reject { |t| t.length < 32 }
    end

    # Constant-time check of a presented token against every configured one.
    def valid_upload_token?(presented)
      return false if presented.blank?

      digest = Digest::SHA256.digest(presented.to_s)
      upload_tokens.any? { |token| ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.digest(token), digest) }
    end
  end
end
