module Spree
  module Api
    module V1
      module Firmware
        # POST /api/v1/firmware/reports (JSON): one install result.
        #
        # Auth optional: a valid bearer links the report to that user; a missing, expired or
        # invalid one files it anonymously (install telemetry is never lost to a stale token).
        #
        # Fields: device (hashed id, 64 hex, required), bundle_id (required), component, from_version,
        # to_version, result (ok|failed|rolled_back|aborted, required), stage, error_code,
        # duration_ms, app_version, platform (ios|android|web), phone_model.
        #
        # 201 { id }; 422 { error, fields }; 429 { error } past the per-IP and per-device limits.
        class ReportsController < Spree::Api::BaseController
          include ::Firmware::ApiResponses

          FIELDS = %i[component from_version to_version result stage error_code app_version platform phone_model].freeze

          skip_before_action :authenticate_user

          def create
            report = FirmwareReport.new(attributes)
            report.bundle = FirmwareBundle.find_by(id: params[:bundle_id].to_s) if params[:bundle_id].present?
            return render_record_errors(report, 'Report could not be saved') unless report.valid?

            keys = { report_ip: ::Firmware::RateLimit.ip_key(request.remote_ip), report_device: report.device_hash }
            return render_error('Too many requests. Try again later.', :too_many_requests) if rate_limited?(keys)

            report.save!
            render json: { id: report.id }, status: :created
          end

          private

          def attributes
            attrs = FIELDS.index_with { |field| string_param(field) }.compact
            attrs[:device_hash] = string_param(:device)
            duration = params[:duration_ms]
            attrs[:duration_ms] = duration if duration.is_a?(Integer) || duration.to_s.match?(/\A\d{1,10}\z/)
            attrs[:user] = current_api_user if current_api_user&.persisted?
            attrs
          end
        end
      end
    end
  end
end
