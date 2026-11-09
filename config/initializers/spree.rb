# The Docker image build runs `assets:precompile` with ASSETS_PRECOMPILE=1 and
# no database (see Dockerfile). Spree reads and writes preferences in the
# database at boot (the setter below, Spree::Auth::Config[:confirmable] in
# Spree::User), so turn that persistence off for that one process: preferences
# fall back to their defaults and nothing connects. Spree's own guard for a
# missing database rescues PG::ConnectionBad, but Rails 6.1 wraps it in
# ActiveRecord::ConnectionNotEstablished, so it doesn't catch this.
Spree::Preferences::Store.instance.persistence = false if ENV['ASSETS_PRECOMPILE'] == '1'

# Configure Spree Preferences
#
# Note: Initializing preferences available within the Admin will overwrite any changes that were made through the user interface when you restart.
#       If you would like users to be able to update a setting with the Admin it should NOT be set here.
#
# Note: If a preference is set here it will be stored within the cache & database upon initialization.
#       Just removing an entry from this initializer will not make the preference value go away.
#       Instead you must either set a new value or remove entry, clear cache, and remove database entry.
# In order to initialize a setting do:
# config.setting_name = 'new value'
Spree.config do |config|
  config.admin_interface_logo = 'beeper_logo.png'
  # Example:
  # Uncomment to stop tracking inventory levels in the application
  # config.track_inventory_levels = false
end

# Configure Spree Dependencies
#
# Note: If a dependency is set here it will NOT be stored within the cache & database upon initialization.
#       Just removing an entry from this initializer will make the dependency value go away.
#
Spree.dependencies do |dependencies|
  # Example:
  # Uncomment to change the default Service handling adding Items to Cart
  # dependencies.cart_add_item_service = 'MyNewAwesomeService'
end

# Spree::Api::Dependencies.storefront_cart_serializer = 'MyRailsApp::CartSerializer'

Spree.user_class = "Spree::User"

# Spree::Config.stock_splitters = [
#   Spree::Stock::Splitter::ShippingCategory,
#   Spree::Stock::Splitter::Weight,
#   Spree::Stock::Splitter::Backordered
# ]