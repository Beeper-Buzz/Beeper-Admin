# Plain JSON errors for the firmware endpoints: `{ "error": "message", "fields": { ... } }`.
# Compact nesting so that loading this file autoloads app/services/firmware.rb first (the classic
# autoloader would otherwise leave a bare Firmware module behind).
module Firmware::ApiResponses
  extend ActiveSupport::Concern

  VERSION_PARAM_MAX = 64

  private

  def render_error(message, status, fields: nil)
    body = { error: message }
    body[:fields] = fields if fields
    render json: body, status: status
  end

  def render_record_errors(record, message = nil)
    render_error(message || record.errors.full_messages.first || 'is invalid', :unprocessable_entity,
                 fields: record.errors.to_hash)
  end

  # A plain string param, stripped; nested hashes or arrays where a string belongs are ignored.
  def string_param(name, source = params)
    value = source[name]
    value = value.to_s if value.is_a?(Numeric)
    value.is_a?(String) ? value.strip.presence : nil
  end

  def rate_limited?(keys)
    !Firmware::RateLimit.allow_all?(keys)
  end
end
