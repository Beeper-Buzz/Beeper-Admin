# db/seed_shipping.rb
# Seeds shipping methods and zones for checkout to work
# Run with: rails runner db/seed_shipping.rb

puts "=== Beeper Shipping Seed ==="

# Ensure shipping category exists
shipping_category = Spree::ShippingCategory.first || Spree::ShippingCategory.create!(name: "Default")
puts "Shipping category: #{shipping_category.name} (id=#{shipping_category.id})"

# Ensure North America zone exists with US + Canada
na_zone = Spree::Zone.find_or_create_by!(name: "North America") do |z|
  z.description = "USA + Canada"
end

us = Spree::Country.find_by(iso: "US")
ca = Spree::Country.find_by(iso: "CA")

[us, ca].compact.each do |country|
  unless na_zone.zone_members.exists?(zoneable: country)
    na_zone.zone_members.create!(zoneable: country)
    puts "  Added #{country.iso} to North America zone"
  end
end
puts "North America zone (id=#{na_zone.id}) — #{na_zone.zone_members.count} members"

# Digital zone (everywhere)
digital_zone = Spree::Zone.find_or_create_by!(name: "Worldwide") do |z|
  z.description = "All countries — digital products"
end
puts "Worldwide zone (id=#{digital_zone.id})"

# Stock location
stock_location = Spree::StockLocation.first || Spree::StockLocation.create!(
  name: "Default",
  default: true,
  active: true,
  backorderable_default: true,
  propagate_all_variants: true,
)

# --- Shipping Methods ---
puts "\n--- Seeding Shipping Methods ---"

# Calculator classes available in Spree 4.x
flat_rate_class = "Spree::Calculator::Shipping::FlatRate"

shipping_methods = [
  {
    name: "USPS First Class",
    admin_name: "usps_first_class",
    zones: [na_zone],
    calculator_type: flat_rate_class,
    calculator_prefs: { amount: 5.99, currency: "USD" },
  },
  {
    name: "USPS Priority Mail",
    admin_name: "usps_priority",
    zones: [na_zone],
    calculator_type: flat_rate_class,
    calculator_prefs: { amount: 9.99, currency: "USD" },
  },
  {
    name: "Free Shipping",
    admin_name: "free_shipping",
    zones: [na_zone],
    calculator_type: flat_rate_class,
    calculator_prefs: { amount: 0.0, currency: "USD" },
  },
  {
    name: "Digital Delivery",
    admin_name: "digital_delivery",
    zones: [na_zone, digital_zone],
    calculator_type: flat_rate_class,
    calculator_prefs: { amount: 0.0, currency: "USD" },
  },
]

shipping_methods.each do |sm_data|
  sm = Spree::ShippingMethod.find_or_initialize_by(admin_name: sm_data[:admin_name])
  sm.name = sm_data[:name]
  sm.display_on = "both"
  sm.shipping_categories = [shipping_category]

  # Assign zones
  sm_data[:zones].each do |zone|
    sm.zones << zone unless sm.zones.include?(zone)
  end

  sm.save!

  # Set up calculator
  calculator = sm.calculator || sm.build_calculator(type: sm_data[:calculator_type])
  calculator.type = sm_data[:calculator_type]
  calculator.save!

  sm_data[:calculator_prefs].each do |key, value|
    calculator.set_preference(key, value)
  end
  calculator.save!

  puts "  Shipping method '#{sm.name}' (id=#{sm.id}) — zones: #{sm.zones.map(&:name).join(', ')} — $#{sm_data[:calculator_prefs][:amount]}"
end

puts "\n=== Shipping seed complete! ==="
