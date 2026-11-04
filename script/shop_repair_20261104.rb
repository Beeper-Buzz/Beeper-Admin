# One-off catalog repair, 2026-11-04 (specs/2026-11-04-shop-featured-and-media-design.md, section 6).
#
#   bin/rails runner script/shop_repair_20261104.rb            # dry run: reads only, prints the plan
#   APPLY=1 bin/rails runner script/shop_repair_20261104.rb    # writes, in one transaction
#
# 1. Keeps product 34 (beeper-8-reservation).
# 2. Retires the seed duplicate 67: its line items on incomplete orders move to 34's master
#    variant (merged into an existing 34 line when the order has one) and those orders are
#    recalculated; then 67 is discontinued (not destroyed) and taken out of Pre-Order.
# 3. Shares product 1's existing image blobs with 34's master variant as new Spree::Image rows,
#    GIF first. No bytes are copied and no blobs are created. Active Storage never purges a
#    blob that another attachment still uses, so the two galleries stay independent.
# 4. Adds 34 to collections/featured at position 1.
#
# Aborts, changing nothing, if a product's id, slug or name is not the expected one, if 34 is
# discontinued or otherwise not available, if a taxon is missing, if 67 is on a completed order, or if an order that
# would change is past checkout, has a payment in progress or a shipment past pending, or
# holds a line not at 34's price (so no cart total changes). Safe to run again: done steps
# are skipped. Prints counts and record ids only.
class ShopRepair20261104
  class Abort < StandardError; end

  RESERVATION_ID = 34
  DUPLICATE_ID = 67
  DEVICE_ID = 1

  EXPECTED = {
    DEVICE_ID => { slug: 'beeper-8', name: 'Beeper Δ8' },
    RESERVATION_ID => { slug: 'beeper-8-reservation', name: 'Beeper Δ8 — Pre-Order Reservation' },
    # FriendlyId appended a UUID to the name-derived slug; only its start is known.
    DUPLICATE_ID => { slug_prefix: 'beeper-8-pre-order-reservation-512eb3fe',
                      name: 'Beeper Δ8 — Pre-Order Reservation' }
  }.freeze

  FEATURED_PERMALINK = 'collections/featured'.freeze
  PRE_ORDER_PERMALINK = 'collections/pre-order'.freeze
  ANIMATED_TYPES = %w[image/gif].freeze
  # An order whose lines move must still be a cart in checkout, with no money in flight.
  CHECKOUT_STATES = %w[cart address delivery payment confirm].freeze
  IDLE_PAYMENT_STATES = %w[checkout failed void invalid].freeze

  attr_reader :apply, :out, :report

  def self.run(apply: ENV['APPLY'] == '1', out: $stdout)
    new(apply: apply, out: out).run
  end

  def initialize(apply:, out: $stdout)
    @apply = apply
    @out = out
    @report = {}
  end

  def run
    say "shop_repair_20261104: #{apply ? 'APPLY' : 'DRY RUN (set APPLY=1 to write)'}"
    if apply
      ActiveRecord::Base.transaction(requires_new: true) do
        load_and_check!
        execute!
      end
    else
      read_only { load_and_check! && plan! }
    end
    print_report
    report
  end

  private

  def say(line)
    out.puts(line)
  end

  # Normalize for comparison: case, dashes and punctuation don't matter.
  def normalize(name)
    name.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^\p{L}\p{N}]+/, ' ').strip
  end

  # The dry run never writes. Outside a surrounding transaction it also asks Postgres to refuse
  # writes for its own transaction.
  def read_only
    if ActiveRecord::Base.connection.open_transactions.zero?
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY')
        yield
        raise ActiveRecord::Rollback
      end
    else
      yield
    end
  end

  def abort!(message)
    raise Abort, "ABORT: #{message}. Nothing was changed."
  end

  def load_and_check!
    @device = check_product(DEVICE_ID)
    @reservation = check_product(RESERVATION_ID)
    @duplicate = check_product(DUPLICATE_ID)
    abort!("product #{RESERVATION_ID} is discontinued") if @reservation.discontinued?
    abort!("product #{RESERVATION_ID} is not available") unless @reservation.available?
    @target_variant = @reservation.master
    abort!("product #{RESERVATION_ID} has no master variant") unless @target_variant
    abort!("product #{RESERVATION_ID} master variant is deleted") if @target_variant.deleted?

    @featured = Spree::Taxon.find_by(permalink: FEATURED_PERMALINK)
    @pre_order = Spree::Taxon.find_by(permalink: PRE_ORDER_PERMALINK)
    abort!("taxon #{FEATURED_PERMALINK} not found") unless @featured
    abort!("taxon #{PRE_ORDER_PERMALINK} not found") unless @pre_order

    @duplicate_variant_ids = Spree::Variant.with_deleted.where(product_id: @duplicate.id).pluck(:id)
    completed = Spree::LineItem.joins(:order).where(variant_id: @duplicate_variant_ids).
                where.not(spree_orders: { completed_at: nil })
    abort!("product #{DUPLICATE_ID} is on #{completed.count} line item(s) of completed orders") if completed.exists?
    check_orders!

    say "checks: ok (products #{DEVICE_ID}, #{RESERVATION_ID}, #{DUPLICATE_ID}; " \
        "taxons #{@featured.id}, #{@pre_order.id}; target variant #{@target_variant.id})"
    true
  end

  def check_product(id)
    product = Spree::Product.with_deleted.find_by(id: id)
    abort!("product #{id} not found") unless product
    abort!("product #{id} is deleted") if product.deleted?

    expected = EXPECTED.fetch(id)
    slug_ok = expected[:slug] ? product.slug == expected[:slug] : product.slug.to_s.start_with?(expected[:slug_prefix])
    abort!("product #{id} slug is not #{expected[:slug] || "#{expected[:slug_prefix]}..."}") unless slug_ok
    abort!("product #{id} name is not \"#{expected[:name]}\"") unless normalize(product.name) == normalize(expected[:name])
    product
  end

  # Every order that would change must be a plain cart in checkout: no payment beyond
  # checkout/failed/void/invalid, no shipment past pending. Every line that ends up on 34's
  # master (moved, merged, or already there) must be at 34's price in that order's currency,
  # so no cart total changes.
  def check_orders!
    lines_to_move.group_by(&:order).each do |order, lines|
      unless CHECKOUT_STATES.include?(order.state)
        abort!("order #{order.id} is in state #{order.state}, not a checkout state")
      end
      busy = order.payments.reject { |payment| IDLE_PAYMENT_STATES.include?(payment.state) }
      abort!("order #{order.id} has #{busy.size} payment(s) in progress") if busy.any?
      if order.shipments.any? { |shipment| shipment.state != 'pending' }
        abort!("order #{order.id} has a shipment that is not pending")
      end

      price = target_price(order.currency)
      abort!("variant #{@target_variant.id} has no #{order.currency} price (order #{order.id})") unless price
      (lines + order.line_items.where(variant_id: @target_variant.id).to_a).each do |line|
        next if line.price == price

        abort!("line item #{line.id} is at #{line.price.to_f} but variant #{@target_variant.id} " \
               "sells at #{price.to_f} in #{order.currency}")
      end
    end
  end

  # Looked up, not Variant#price_in, which builds an unsaved Price when there is none.
  def target_price(currency)
    @target_variant.prices.find_by(currency: currency.to_s.upcase)&.amount
  end

  # --- what would change ----------------------------------------------------------------

  def lines_to_move
    Spree::LineItem.joins(:order).where(variant_id: @duplicate_variant_ids, spree_orders: { completed_at: nil }).
      order(:id).to_a
  end

  def source_images
    variant_ids = @device.variants_including_master.reorder(is_master: :desc, position: :asc, id: :asc).pluck(:id)
    images = Spree::Image.where(viewable_type: 'Spree::Variant', viewable_id: variant_ids).
             includes(attachment_attachment: :blob).to_a
    images.select! { |image| image.attachment.attached? }
    images.sort_by! { |image| [variant_ids.index(image.viewable_id), image.position.to_i, image.id] }
    # GIFs first, the rest keep their order.
    images.partition { |image| ANIMATED_TYPES.include?(image.attachment.content_type) }.flatten
  end

  def images_to_share
    present = @target_variant.images.includes(:attachment_attachment).map { |image| image.attachment.blob_id }.compact
    source_images.reject { |image| present.include?(image.attachment.blob_id) }
  end

  def featured_classification
    Spree::Classification.find_by(product_id: @reservation.id, taxon_id: @featured.id)
  end

  # Per order, as move_line_items! does it: the first line of 67 moves when the order has no
  # line of 34's master yet; every other line merges into that one.
  def planned_moves_and_merges
    moves = []
    merges = []
    lines_to_move.group_by(&:order_id).each do |order_id, lines|
      has_target = Spree::LineItem.where(order_id: order_id, variant_id: @target_variant.id).exists?
      lines.each do |line|
        (has_target ? merges : moves) << line
        has_target = true
      end
    end
    [moves, merges]
  end

  def plan!
    moves, merges = planned_moves_and_merges
    report[:line_items_moved] = moves.map(&:id)
    report[:line_items_merged] = merges.map(&:id)
    report[:orders_recalculated] = (moves + merges).map(&:order_id).uniq
    report[:discontinued] = !@duplicate.discontinued?
    report[:removed_from_pre_order] = @duplicate.classifications.where(taxon_id: @pre_order.id).exists?
    report[:images_shared_blob_ids] = images_to_share.map { |image| image.attachment.blob_id }
    report[:new_image_ids] = []
    existing = featured_classification
    report[:featured] = existing.nil?
    report[:featured_position] = existing&.position
  end

  # --- writes ---------------------------------------------------------------------------

  def existing_target_line(order)
    order.line_items.find_by(variant_id: @target_variant.id)
  end

  def execute!
    plan!
    move_line_items!
    retire_duplicate!
    share_images!
    feature_reservation!
  end

  def move_line_items!
    lines_to_move.group_by(&:order).each do |order, lines|
      # Like any cart edit: drop proposed shipments so checkout re-plans them.
      order.ensure_updated_shipments
      target_line = nil
      lines.each do |line|
        existing = existing_target_line(order)
        if existing
          existing.quantity += line.quantity
          existing.save!
          line.reload.destroy!
          target_line = existing
        else
          line.variant = @target_variant
          line.price = target_price(order.currency) # equal to line.price: check_orders!
          line.cost_price = @target_variant.cost_price
          line.save!
          target_line = line
        end
      end
      Spree::Dependencies.cart_recalculate_service.constantize.call(order: order.reload, line_item: target_line.reload)
    end
  end

  def retire_duplicate!
    @duplicate.discontinue! unless @duplicate.discontinued?
    Spree::Classification.where(product_id: @duplicate.id, taxon_id: @pre_order.id).destroy_all
  end

  def share_images!
    images = images_to_share
    created = images.map do |source|
      image = Spree::Image.new(viewable: @target_variant, alt: source.alt)
      image.attachment.attach(source.attachment.blob)
      image.save!
      image
    end
    # GIF at the top of 34's gallery, ahead of anything already there.
    created.reverse_each { |image| image.insert_at(1) }
    report[:new_image_ids] = created.map(&:id)
  end

  def feature_reservation!
    return if featured_classification

    classification = Spree::Classification.create!(product: @reservation, taxon: @featured)
    classification.insert_at(1)
    report[:featured_position] = 1
  end

  def print_report
    verb = apply ? '' : 'would be '
    say "line items #{verb}moved to variant #{@target_variant&.id}: #{report[:line_items_moved].size} #{report[:line_items_moved].inspect}"
    say "line items #{verb}merged into an existing line: #{report[:line_items_merged].size} #{report[:line_items_merged].inspect}"
    say "orders #{verb}recalculated: #{report[:orders_recalculated].size} #{report[:orders_recalculated].inspect}"
    say "product #{DUPLICATE_ID} #{verb}discontinued: #{report[:discontinued] ? 'yes' : 'no (already)'}"
    say "product #{DUPLICATE_ID} #{verb}removed from taxon #{@pre_order&.id}: #{report[:removed_from_pre_order] ? 'yes' : 'no (not a member)'}"
    say "images #{verb}added to variant #{@target_variant&.id}: #{report[:images_shared_blob_ids].size} " \
        "(blob ids #{report[:images_shared_blob_ids].inspect}, new image ids #{report[:new_image_ids].inspect})"
    featured = if report[:featured]
                 "#{verb}added at position 1"
               else
                 "no (already a member, position #{report[:featured_position]})"
               end
    say "product #{RESERVATION_ID} in taxon #{@featured&.id}: #{featured}"
    say(apply ? 'done.' : 'dry run: nothing was written.')
  end
end

if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  begin
    ShopRepair20261104.run
  rescue ShopRepair20261104::Abort => e
    warn e.message
    exit 1
  end
end
