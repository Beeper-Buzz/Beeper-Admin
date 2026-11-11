# config/initializers/cors.rb

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    if Rails.env.development?
      origins '*'
    else
      # Use comma-separated list: ALLOWED_ORIGINS=https://dna.com,https://www.dna.com
      origins ENV['ALLOWED_ORIGINS']&.split(',') || 'https://dna-admin-staging.instinct.is'
    end

    resource '*',
      headers: :any,
      methods: [:get, :post, :patch, :put, :delete, :options, :head]
  end

  # The firmware recovery/update web page calls check and reports from the browser. Only those two
  # endpoints, for these origins (comma-separated in FIRMWARE_ALLOWED_ORIGINS).
  allow do
    origins(*(ENV['FIRMWARE_ALLOWED_ORIGINS'].presence || 'https://beeper.buzz,https://www.beeper.buzz').split(',').map(&:strip))

    resource '/api/v1/firmware/check', headers: :any, methods: [:get, :head, :options]
    resource '/api/v1/firmware/reports', headers: :any, methods: [:post, :options]
  end
end
