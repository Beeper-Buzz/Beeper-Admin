module Spree
  module Admin
    # Small pieces of the Firmware tab: state and result badges, short hashes.
    module FirmwareBundlesHelper
      FIRMWARE_STATE_BADGES = { 'draft' => 'badge-secondary', 'published' => 'badge-success', 'paused' => 'badge-warning',
                                'revoked' => 'badge-danger' }.freeze
      FIRMWARE_RESULT_BADGES = { 'ok' => 'badge-success', 'failed' => 'badge-danger', 'rolled_back' => 'badge-warning',
                                 'aborted' => 'badge-secondary' }.freeze

      def firmware_state_badge(bundle)
        content_tag(:span, bundle.state, class: "badge #{FIRMWARE_STATE_BADGES.fetch(bundle.state, 'badge-light')}")
      end

      def firmware_result_badge(result, count = nil)
        label = count ? "#{result} #{count}" : result
        content_tag(:span, label, class: "badge #{FIRMWARE_RESULT_BADGES.fetch(result, 'badge-light')}")
      end

      def firmware_short_hash(hex, length = 12)
        return '' if hex.blank?

        content_tag(:code, "#{hex.first(length)}…", title: hex)
      end
    end
  end
end
