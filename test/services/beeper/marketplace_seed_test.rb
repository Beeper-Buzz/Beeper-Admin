require 'test_helper'
require 'rake'

# Beeper's marketplace seed data and the Starter Kit (spec §1.5, §3.5).
class Beeper::MarketplaceSeedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  WAV = DigitalAssetsTestHelper::WAV_BYTES

  setup do
    digital_store
  end

  def counts
    {
      taxonomies: Spree::Taxonomy.count, taxons: Spree::Taxon.count, roles: Spree::Role.count,
      shipping_categories: Spree::ShippingCategory.count, products: Spree::Product.count,
      properties: Spree::Property.count, product_properties: Spree::ProductProperty.count
    }
  end

  # A kit directory like the app's generator writes: WAVs plus manifest.json.
  def kit_dir(samples: 16, pack_id: 'starter-kit', extra: {}, bytes: WAV)
    dir = Pathname.new(Dir.mktmpdir('starter-kit'))
    list = Array.new(samples) do |i|
      name = format('%02d-sound.wav', i + 1)
      File.binwrite(dir.join(name), bytes + [i].pack('C'))
      { 'file' => name, 'name' => "Sound #{i + 1}", 'root_note' => 60, 'one_shot' => true, 'pad' => i + 1 }
    end
    File.write(dir.join('manifest.json'), JSON.generate({ 'format' => 1, 'pack_id' => pack_id, 'samples' => list }.merge(extra)))
    dir
  end

  test 'seed creates the marketplace taxons, the Digital shipping category, the creator role and the kit product' do
    result = Beeper::Marketplace::Seed.call

    root = Creators.marketplace_taxon
    assert root, 'marketplace taxon by permalink'
    assert_equal 'Marketplace', root.name
    assert_equal %w[Sample\ Packs Effects Visualizers], root.children.order(:lft).pluck(:name)
    assert_equal %w[marketplace/sample-packs marketplace/effects marketplace/visualizers],
                 root.children.order(:lft).pluck(:permalink)
    assert Spree::ShippingCategory.exists?(name: 'Digital')
    assert Spree::Role.exists?(name: 'creator')

    kit = result[:starter_kit]
    assert_equal 'Beeper Starter Kit', kit.name
    assert_equal 'beeper-starter-kit', kit.slug
    assert_equal 0, kit.price.to_i
    assert_equal 'Digital', kit.shipping_category.name
    assert_equal 'true', kit.property('claimable')
    assert_includes kit.taxons, root
    assert_includes kit.taxons, root.children.find_by(name: 'Sample Packs')
    assert_nil kit.available_on, 'the kit stays off sale until its files are published'
    assert kit.description.present?
  end

  test 'seed twice creates no duplicates' do
    Beeper::Marketplace::Seed.call
    before = counts
    Beeper::Marketplace::Seed.call
    assert_equal before, counts
  end

  test 'seed reuses an existing marketplace taxon' do
    taxonomy = Spree::Taxonomy.create!(name: 'Shop')
    existing = Spree::Taxon.create!(name: 'Marketplace', taxonomy: taxonomy, parent: taxonomy.root)
    existing.update!(permalink: 'marketplace')

    Beeper::Marketplace::Seed.call

    assert_equal existing, Creators.marketplace_taxon
    assert_equal 1, Spree::Taxon.where(permalink: 'marketplace').count
    assert_equal 3, existing.reload.children.count
  end

  test 'starter_kit attaches the files and publishes a valid sample_pack, on sale and claimable' do
    dir = kit_dir
    result = Beeper::Marketplace::StarterKit.call(dir)

    assert_equal :published, result[:status]
    asset = result[:asset]
    assert asset.published?
    assert_equal 1, asset.version
    assert_equal 'sample_pack', asset.kind
    assert_equal 'starter-kit', asset.manifest['pack_id']
    assert_equal 16, asset.files.attachments.count
    assert_equal (1..16).map { |i| format('%02d-sound.wav', i) }, asset.file_entries.map { |f| f[:filename] }.sort
    assert asset.file_entries.all? { |f| f[:content_type] == 'audio/wav' }
    with_beeper_kinds do
      assert_empty Beeper::Manifests::SamplePack.call(asset.manifest, asset)
      assert asset.reload.valid?, asset.errors.full_messages.inspect
    end

    product = result[:product].reload
    assert product.available?
    assert DigitalAssets::Claim.claimable?(product.master)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  def sha256_entries(asset)
    Array(asset.reload.manifest['files']).to_h { |entry| [entry['filename'], entry['sha256']] }
  end

  test 'starter_kit stores the files sha256 before returning, without a background job' do
    dir = kit_dir
    asset = nil
    assert_no_enqueued_jobs(only: DigitalAssets::ChecksumJob) { asset = Beeper::Marketplace::StarterKit.call(dir)[:asset] }

    expected = Dir[dir.join('*.wav')].to_h { |path| [File.basename(path), Digest::SHA256.file(path).hexdigest] }
    assert_equal expected, sha256_entries(asset)
    assert asset.file_entries.all? { |file| file[:sha256].present? }
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  test 'starter_kit unchanged run backfills missing sha256 entries' do
    dir = kit_dir
    asset = Beeper::Marketplace::StarterKit.call(dir)[:asset]
    expected = sha256_entries(asset)
    assert_equal 16, expected.compact.size
    asset.update_columns(manifest: asset.manifest.except('files'))

    result = Beeper::Marketplace::StarterKit.call(dir)

    assert_equal :unchanged, result[:status]
    assert_equal expected, sha256_entries(asset)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  test 'starter_kit run again with the same files changes nothing' do
    dir = kit_dir
    first = Beeper::Marketplace::StarterKit.call(dir)
    blobs = ActiveStorage::Blob.count

    second = Beeper::Marketplace::StarterKit.call(dir)

    assert_equal :unchanged, second[:status]
    assert_equal first[:asset], second[:asset]
    assert_equal 1, Spree::DigitalAsset.where(variant_id: first[:product].master.id).count
    assert_equal blobs, ActiveStorage::Blob.count
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  test 'starter_kit with changed files publishes the next version' do
    dir = kit_dir
    first = Beeper::Marketplace::StarterKit.call(dir)
    File.binwrite(dir.join('03-sound.wav'), WAV + 'changed'.b)

    second = Beeper::Marketplace::StarterKit.call(dir)

    assert_equal :published, second[:status]
    assert_equal 2, second[:asset].version
    assert_equal second[:asset], first[:product].master.reload.live_digital_asset
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  test 'starter_kit refuses a manifest without pack_id "starter-kit", an invalid one, or a missing file' do
    dir = kit_dir(pack_id: 'my-pack')
    error = assert_raises(Beeper::Marketplace::StarterKit::Invalid) { Beeper::Marketplace::StarterKit.call(dir) }
    assert_includes error.message, 'pack_id must be "starter-kit"'

    dir = kit_dir(extra: { 'format' => 2 })
    error = assert_raises(Beeper::Marketplace::StarterKit::Invalid) { Beeper::Marketplace::StarterKit.call(dir) }
    assert_includes error.message, 'format must be 1'

    dir = kit_dir
    File.delete(dir.join('07-sound.wav'))
    error = assert_raises(Beeper::Marketplace::StarterKit::Invalid) { Beeper::Marketplace::StarterKit.call(dir) }
    assert_includes error.message, '07-sound.wav'

    assert_equal 0, Spree::DigitalAsset.count
  end

  test 'rake beeper:marketplace:seed and beeper:marketplace:starter_kit[dir]' do
    Rails.application.load_tasks unless Rake::Task.task_defined?('beeper:marketplace:seed')
    dir = kit_dir

    assert_output(/Marketplace seeded/) { Rake::Task['beeper:marketplace:seed'].execute }
    assert_output(/Starter Kit version 1 published/) do
      Rake::Task['beeper:marketplace:starter_kit'].execute(Rake::TaskArguments.new([:dir], [dir.to_s]))
    end
    assert_output(/Starter Kit unchanged/) do
      Rake::Task['beeper:marketplace:starter_kit'].execute(Rake::TaskArguments.new([:dir], [dir.to_s]))
    end
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
