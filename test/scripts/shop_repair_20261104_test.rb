require 'test_helper'
load Rails.root.join('script', 'shop_repair_20261104.rb').to_s

# script/shop_repair_20261104.rb against a copy of the production catalog's shape
# (products 1, 34 and 67, the Featured and Pre-Order taxons, carts holding 67).
class ShopRepair20261104Test < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  RESERVATION_NAME = 'Beeper Δ8 — Pre-Order Reservation'.freeze

  setup do
    # Explicit ids 1, 34 and 67 below; keep generated ids clear of them.
    %w[spree_products spree_variants].each do |table|
      ActiveRecord::Base.connection.execute(
        "SELECT setval('#{table}_id_seq', GREATEST((SELECT last_value FROM #{table}_id_seq), 1000))"
      )
    end
    @store = media_store
    @shipping_category = Spree::ShippingCategory.first_or_create!(name: 'Default')

    collections = Spree::Taxonomy.create!(name: 'Collections')
    @featured = Spree::Taxon.create!(name: 'Featured', parent: collections.root, taxonomy: collections)
    @pre_order = Spree::Taxon.create!(name: 'Pre-Order', parent: collections.root, taxonomy: collections)

    @device = product(1, 'Beeper Δ8', 'beeper-8', 199, available_on: nil)
    color = Spree::OptionType.create!(name: "color-#{SecureRandom.hex(3)}", presentation: 'Color')
    black = color.option_values.create!(name: 'black', presentation: '#000000')
    @device.option_types << color
    @black = @device.variants.create!(sku: 'BEEPER-D8-BLK', price: 199, option_values: [black])
    @gif = media_image(@device.master, GIF_BYTES, 'beeper-teaser-800-light.gif', 'image/gif', width: 800, height: 500)
    @card = media_image(@device.master, JPG_BYTES, 'Back-Moo_Rack-Card-web.jpg', 'image/jpeg')
    @black_front = media_image(@black, JPG_BYTES, 'black-front.jpg', 'image/jpeg')
    @black_back = media_image(@black, JPG_BYTES, 'black-back.jpg', 'image/jpeg')
    # The rack card sits above the GIF on the master and the black JPGs tie with it at
    # position 1: the GIF must still come first.
    @card.update_columns(position: 1)
    @gif.update_columns(position: 2)

    @reservation = product(34, RESERVATION_NAME, 'beeper-8-reservation', 49)
    @duplicate = product(67, RESERVATION_NAME, 'beeper-8-pre-order-reservation-512eb3fe-0d1c-4d0e-9d55-6e1f0b6f8a77', 49)
    @sample_pack = product(6, 'Starter Sample Pack', 'starter-sample-pack', 9.99)

    [@device, @reservation, @duplicate].each { |p| p.taxons << @pre_order }
    [@device, @sample_pack].each { |p| p.taxons << @featured }

    # Cart with only 67, cart with 34 and 67, and a completed order with 34.
    @cart_only_dup = order_with(@duplicate.master => 1)
    @cart_both = order_with(@reservation.master => 1, @duplicate.master => 2)
    @completed = order_with(@reservation.master => 1)
    @completed.update_columns(completed_at: 1.day.ago, state: 'complete')
  end

  def product(id, name, slug, price, available_on: 1.month.ago)
    record = Spree::Product.new(id: id, name: name, price: price, available_on: available_on,
                                shipping_category: @shipping_category)
    record.stores << @store if record.respond_to?(:stores)
    record.save!
    record.update_columns(slug: slug)
    # Reservations are backorderable and never sell out.
    record.master.update_columns(track_inventory: false)
    record.reload
  end

  def order_with(lines)
    order = Spree::Order.create!(store: @store, currency: 'USD', email: "buyer-#{SecureRandom.hex(4)}@example.com")
    lines.each do |variant, quantity|
      Spree::Dependencies.cart_add_item_service.constantize.call(order: order, variant: variant, quantity: quantity)
    end
    order.update_with_updater!
    order.reload
  end

  def run_repair(apply:)
    out = StringIO.new
    report = ShopRepair20261104.run(apply: apply, out: out)
    [report, out.string]
  end

  TABLES = %w[spree_products spree_variants spree_line_items spree_orders spree_assets spree_products_taxons
              active_storage_blobs active_storage_attachments spree_adjustments spree_shipments].freeze

  # Row counts plus the columns the repair would touch.
  def snapshot
    counts = TABLES.index_with { |t| ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}").to_i }
    counts.merge(
      line_items: Spree::LineItem.order(:id).pluck(:id, :order_id, :variant_id, :quantity, :price).map { |r| r.map(&:to_s) },
      orders: Spree::Order.order(:id).pluck(:id, :item_total, :total, :state).map { |r| r.map(&:to_s) },
      products: Spree::Product.with_deleted.order(:id).pluck(:id, :discontinue_on, :deleted_at).map { |r| r.map(&:to_s) },
      classifications: Spree::Classification.order(:id).pluck(:id, :product_id, :taxon_id, :position),
      images: Spree::Image.order(:id).pluck(:id, :viewable_id, :position)
    )
  end

  test 'dry run changes nothing and reports the plan' do
    before = snapshot
    report, output = run_repair(apply: false)
    assert_equal before, snapshot

    assert_includes output, 'DRY RUN'
    assert_includes output, 'nothing was written'
    assert_equal 1, report[:line_items_moved].size
    assert_equal 1, report[:line_items_merged].size
    assert_equal [@cart_only_dup.id, @cart_both.id].sort, report[:orders_recalculated].sort
    assert report[:discontinued]
    assert report[:removed_from_pre_order]
    assert_equal 4, report[:images_shared_blob_ids].size
    assert report[:featured]
    refute @duplicate.reload.discontinued?
  end

  test 'apply moves the cart line to 34 master and merges when the order already has one' do
    run_repair(apply: true)
    target = @reservation.master

    lines = @cart_only_dup.reload.line_items.to_a
    assert_equal [target.id], lines.map(&:variant_id)
    assert_equal 1, lines.first.quantity
    assert_equal 49, lines.first.price.to_i

    lines = @cart_both.reload.line_items.to_a
    assert_equal [target.id], lines.map(&:variant_id)
    assert_equal 3, lines.first.quantity

    dup_variants = Spree::Variant.with_deleted.where(product_id: 67).ids
    assert_equal 0, Spree::LineItem.where(variant_id: dup_variants).count
  end

  test 'apply recalculates the orders' do
    run_repair(apply: true)
    assert_equal 49, @cart_only_dup.reload.item_total.to_i
    assert_equal 147, @cart_both.reload.item_total.to_i
    assert_equal 3, @cart_both.item_count
    assert_equal @cart_both.item_total, @cart_both.total
  end

  test 'apply leaves the completed order alone' do
    before = @completed.line_items.pluck(:id, :variant_id, :quantity)
    run_repair(apply: true)
    assert_equal before, @completed.reload.line_items.pluck(:id, :variant_id, :quantity)
  end

  test 'apply discontinues 67 and removes it from Pre-Order, without deleting it' do
    run_repair(apply: true)
    @duplicate.reload
    assert @duplicate.discontinued?
    refute @duplicate.deleted?
    refute_includes @pre_order.reload.products.ids, 67
    assert_includes @pre_order.products.ids, 34
  end

  test 'apply shares product 1 blobs with 34 master as new images, GIF first, no new blobs' do
    blobs_before = ActiveStorage::Blob.count
    source_blob_ids = [@gif, @card, @black_front, @black_back].map { |i| i.attachment.blob_id }
    report, = run_repair(apply: true)

    assert_equal blobs_before, ActiveStorage::Blob.count
    images = @reservation.master.images.reload.to_a
    assert_equal 4, images.size
    assert_equal [1, 2, 3, 4], images.map(&:position)
    assert_equal @gif.attachment.blob_id, images.first.attachment.blob_id
    assert_equal 'image/gif', images.first.attachment.content_type
    assert_equal source_blob_ids.sort, images.map { |i| i.attachment.blob_id }.sort
    # GIF, then master's JPG, then the black variant's in their order.
    assert_equal source_blob_ids, images.map { |i| i.attachment.blob_id }
    assert_equal 'alt beeper-teaser-800-light.gif', images.first.alt
    assert_equal images.map(&:id), report[:new_image_ids]
    # Product 1's own gallery is untouched.
    assert_equal 4, @device.reload.variant_images.count
  end

  test 'apply adds 34 to Featured at position 1' do
    run_repair(apply: true)
    ordered = Spree::Classification.where(taxon: @featured).order(:position).pluck(:product_id)
    assert_equal [34, 1, 6], ordered
    assert_equal 1, Spree::Classification.find_by!(taxon: @featured, product_id: 34).position
  end

  test 'a second apply is a no-op' do
    run_repair(apply: true)
    before = snapshot
    report, output = run_repair(apply: true)
    assert_equal before, snapshot
    assert_empty report[:line_items_moved]
    assert_empty report[:line_items_merged]
    assert_empty report[:orders_recalculated]
    refute report[:discontinued]
    refute report[:removed_from_pre_order]
    assert_empty report[:images_shared_blob_ids]
    refute report[:featured]
    assert_includes output, 'already a member, position 1'
  end

  test 'output carries counts and ids only' do
    _, dry = run_repair(apply: false)
    _, applied = run_repair(apply: true)
    orders = [@cart_only_dup, @cart_both, @completed]
    [dry, applied].each do |output|
      orders.each do |order|
        refute_includes output, order.number
        refute_includes output, order.email
      end
      refute_match(/@/, output)
    end
  end

  test 'aborts with no changes when 67 is on a completed order' do
    order_with(@duplicate.master => 1).update_columns(completed_at: 1.hour.ago, state: 'complete')
    before = snapshot
    error = assert_raises(ShopRepair20261104::Abort) { run_repair(apply: true) }
    assert_match(/completed orders/, error.message)
    assert_equal before, snapshot
  end

  test 'aborts with no changes when a slug or name does not match' do
    before = snapshot
    @reservation.update_columns(slug: 'something-else')
    error = assert_raises(ShopRepair20261104::Abort) { run_repair(apply: true) }
    assert_match(/product 34 slug/, error.message)
    @reservation.update_columns(slug: 'beeper-8-reservation')

    @device.update_columns(name: 'Other Device')
    error = assert_raises(ShopRepair20261104::Abort) { run_repair(apply: true) }
    assert_match(/product 1 name/, error.message)
    @device.update_columns(name: 'Beeper Δ8')

    @duplicate.update_columns(slug: 'beeper-8-pre-order-reservation')
    error = assert_raises(ShopRepair20261104::Abort) { run_repair(apply: false) }
    assert_match(/product 67 slug/, error.message)
    @duplicate.update_columns(slug: 'beeper-8-pre-order-reservation-512eb3fe-0d1c-4d0e-9d55-6e1f0b6f8a77')

    assert_equal before.except(:products), snapshot.except(:products)
    refute @duplicate.reload.discontinued?
  end

  def assert_aborts_unchanged(pattern)
    before = snapshot
    error = assert_raises(ShopRepair20261104::Abort) { run_repair(apply: true) }
    assert_match pattern, error.message
    assert_equal before, snapshot
    error = assert_raises(ShopRepair20261104::Abort) { run_repair(apply: false) }
    assert_match pattern, error.message
  end

  def check_payment(order, state)
    method = Spree::PaymentMethod::Check.first_or_create!(name: 'Check')
    payment = order.payments.create!(payment_method: method, amount: order.total)
    payment.update_columns(state: state)
    payment
  end

  test 'aborts with no changes when an order holding 67 is not in checkout' do
    @cart_only_dup.update_columns(state: 'awaiting_return')
    assert_aborts_unchanged(/order #{@cart_only_dup.id} is in state awaiting_return/)
  end

  test 'aborts with no changes when an order holding 67 has a payment in progress' do
    check_payment(@cart_both, 'pending')
    assert_aborts_unchanged(/order #{@cart_both.id} has 1 payment\(s\) in progress/)
  end

  test 'a checkout or failed payment does not block the move' do
    check_payment(@cart_both, 'checkout')
    check_payment(@cart_only_dup, 'failed')
    report, = run_repair(apply: true)
    assert_equal [@cart_only_dup.id, @cart_both.id].sort, report[:orders_recalculated].sort
    assert_equal 147, @cart_both.reload.item_total.to_i
  end

  test 'aborts with no changes when an order holding 67 has a shipment past pending' do
    location = Spree::StockLocation.first_or_create!(name: 'Default')
    shipment = @cart_only_dup.shipments.create!(stock_location: location)
    shipment.update_columns(state: 'ready')
    assert_aborts_unchanged(/order #{@cart_only_dup.id} has a shipment that is not pending/)
  end

  test 'aborts with no changes when 34 does not sell at the price the cart line has' do
    @reservation.master.default_price.update_columns(amount: 59)
    assert_aborts_unchanged(/line item \d+ is at 49.0 but variant #{@reservation.master.id} sells at 59.0/)
  end

  test 'aborts with no changes when an existing 34 line is at another price' do
    @cart_both.line_items.find_by!(variant_id: @reservation.master.id).update_columns(price: 45)
    assert_aborts_unchanged(/line item \d+ is at 45.0 but variant #{@reservation.master.id} sells at 49.0/)
  end

  test 'aborts with no changes when 34 has no price in the order currency' do
    @cart_only_dup.update_columns(currency: 'EUR')
    @cart_only_dup.line_items.update_all(currency: 'EUR')
    assert_aborts_unchanged(/variant #{@reservation.master.id} has no EUR price/)
  end

  test 'aborts when 34 is discontinued' do
    @reservation.update_columns(discontinue_on: 1.day.ago)
    assert_aborts_unchanged(/product 34 is discontinued/)
  end

  # Two lines of 67 (two of its variants) in one order: the first is moved, the second merged
  # into it. The dry run must report what apply then does.
  test 'the dry run reports moves and merges exactly as apply performs them' do
    size = Spree::OptionType.create!(name: "size-#{SecureRandom.hex(3)}", presentation: 'Size')
    big = size.option_values.create!(name: 'big', presentation: 'Big')
    @duplicate.option_types << size
    dup_big = @duplicate.variants.create!(sku: 'DUP-BIG', price: 49, option_values: [big])
    dup_big.update_columns(track_inventory: false)
    two = order_with(@duplicate.master => 1, dup_big => 1)
    first_line, second_line = two.line_items.order(:id).ids
    assert second_line

    planned, = run_repair(apply: false)
    assert_includes planned[:line_items_moved], first_line
    assert_includes planned[:line_items_merged], second_line
    applied, = run_repair(apply: true)
    %i[line_items_moved line_items_merged orders_recalculated].each do |key|
      assert_equal planned[key].sort, applied[key].sort, key
    end
    lines = two.reload.line_items.to_a
    assert_equal [first_line], lines.map(&:id)
    assert_equal [[@reservation.master.id, 2]], lines.map { |l| [l.variant_id, l.quantity] }
    assert_equal 98, two.item_total.to_i
  end

  test 'names compare without regard to case or dash style' do
    @reservation.update_columns(name: 'Beeper Δ8 - Pre-Order Reservation')
    report, = run_repair(apply: false)
    assert report[:featured]
  end

  test 'aborts when a product is missing' do
    Spree::Classification.where(product_id: 67).delete_all
    Spree::LineItem.where(variant_id: Spree::Variant.with_deleted.where(product_id: 67).ids).delete_all
    Spree::Variant.with_deleted.where(product_id: 67).delete_all
    Spree::Product.with_deleted.where(id: 67).delete_all
    error = assert_raises(ShopRepair20261104::Abort) { run_repair(apply: false) }
    assert_match(/product 67 not found/, error.message)
  end

  # Verifies the spec's claim (section 6.3) rather than trusting it: in Rails 6.1, removing an
  # image from 34 enqueues a purge of its blob, and Blob#purge refuses (before_destroy raises
  # InvalidForeignKey, which purge rescues) while another attachment still uses the blob.
  test 'deleting an image from 34 leaves product 1 blob and image intact' do
    run_repair(apply: true)
    shared = @reservation.master.images.reload.first
    blob = shared.attachment.blob

    perform_enqueued_jobs { shared.destroy! }
    assert ActiveStorage::Blob.exists?(blob.id)
    assert blob.service.exist?(blob.key)
    assert @gif.reload.attachment.attached?
    assert_equal blob.id, @gif.attachment.blob_id
    assert_equal GIF_BYTES, @gif.attachment.download

    # An explicit, synchronous purge of 34's attachment doesn't take the blob either.
    other = @reservation.master.images.reload.first
    other_blob = other.attachment.blob
    other.attachment.purge
    assert ActiveStorage::Blob.exists?(other_blob.id)
    assert other_blob.service.exist?(other_blob.key)
    assert_equal 4, @device.reload.variant_images.count
  end

  # Control for the test above: the purge job does run and does delete a blob nothing else uses.
  test 'deleting an image whose blob is not shared purges the blob' do
    lone = media_image(@sample_pack.master, JPG_BYTES, 'lone.jpg', 'image/jpeg')
    blob = lone.attachment.blob
    perform_enqueued_jobs { lone.destroy! }
    refute ActiveStorage::Blob.exists?(blob.id)
    refute blob.service.exist?(blob.key)
  end
end

# The dry run as production runs it: outside any transaction, so the script opens its own and
# makes it READ ONLY. Not transactional, so it writes nothing that would need cleaning up.
class ShopRepair20261104ReadOnlyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test 'the dry run transaction refuses writes' do
    assert_equal 0, ActiveRecord::Base.connection.open_transactions
    repair = ShopRepair20261104.new(apply: false, out: StringIO.new)
    name = "read-only-probe-#{SecureRandom.hex(4)}"
    error = assert_raises(ActiveRecord::StatementInvalid) do
      repair.send(:read_only) { Spree::Role.create!(name: name) }
    end
    assert_match(/read-only transaction/, error.message)
    refute Spree::Role.exists?(name: name)
  end

  test 'a dry run outside a transaction aborts cleanly on an empty catalog' do
    error = assert_raises(ShopRepair20261104::Abort) { ShopRepair20261104.run(apply: false, out: StringIO.new) }
    assert_match(/product 1 not found/, error.message)
    assert_equal 0, ActiveRecord::Base.connection.open_transactions
  end
end
