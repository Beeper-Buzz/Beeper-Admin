# A default store and an admin user for a Heroku review app, so it can be signed in to.
# Run by bin/review-app-setup (app.json's postdeploy) after it loads db/schema.rb. db:seed is
# not used: it loads sample data, asks for input and fails in production on loyalty points.
#
#   bundle exec rails runner db/review_app_setup.rb
#
# Safe to run again; it only creates what is missing.

store = Spree::Store.default
unless store.persisted?
  host = ENV['HEROKU_APP_NAME'].present? ? "#{ENV['HEROKU_APP_NAME']}.herokuapp.com" : 'localhost'
  store = Spree::Store.create!(
    name: ENV.fetch('SITE_TITLE', 'Review App'),
    url: host,
    code: 'review',
    mail_from_address: 'no-reply@example.com',
    default_currency: 'USD',
    default: true
  )
end

email = ENV.fetch('ADMIN_EMAIL', 'admin@example.com')
password = ENV.fetch('ADMIN_PASSWORD') { abort 'Set ADMIN_PASSWORD' }

admin = Spree.user_class.find_by(email: email) ||
        Spree.user_class.create!(email: email, password: password, password_confirmation: password)
admin.spree_roles << Spree::Role.find_or_create_by!(name: 'admin') unless admin.has_spree_role?('admin')

puts "Review app ready: store #{store.url}, admin #{email}"
