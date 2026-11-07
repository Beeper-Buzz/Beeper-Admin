# Error + performance reporting for the Spree admin/API app.
# Sentry project: material-instinct-llc/beeper-admin
#
# No SENTRY_DSN means no configuration at all, so development, test and any
# environment that has not been given a DSN stay silent.
if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.environment = ENV['SENTRY_ENVIRONMENT'] || Rails.env

    # This app is the Spree storefront API behind admin.beeper.buzz as well as
    # the admin UI. Requests carry customer addresses, order contents and OAuth
    # tokens, so do not let the SDK attach request bodies, cookies or IPs.
    config.send_default_pii = false

    # Traces are billed per event; the admin UI is low traffic but the v2
    # storefront API is not. Override per environment with SENTRY_TRACES_SAMPLE_RATE.
    config.traces_sample_rate = (ENV['SENTRY_TRACES_SAMPLE_RATE'] || 0.1).to_f

    # Spree raises these for ordinary 404s and bot traffic; they are not defects.
    config.excluded_exceptions += [
      'ActiveRecord::RecordNotFound',
      'ActionController::RoutingError',
      'ActionController::UnknownFormat',
      'ActionController::InvalidAuthenticityToken'
    ]

    # Report the deployed revision so an issue can be traced to a Heroku release.
    config.release = ENV['HEROKU_SLUG_COMMIT'] || ENV['SOURCE_VERSION']
  end
end
