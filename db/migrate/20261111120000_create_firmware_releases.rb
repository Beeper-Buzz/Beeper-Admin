# Device firmware releases: bundles of signed images per hardware revision, the images (files in
# ActiveStorage), install reports from clients, and the rate counters of the public endpoints.
# Self-contained: no Spree tables except the optional user on a report.
class CreateFirmwareReleases < ActiveRecord::Migration[6.1]
  def change
    create_table :firmware_bundles do |t|
      t.string :hw_rev, null: false
      t.string :version, null: false
      t.string :channel, null: false, default: 'internal'
      t.string :state, null: false, default: 'draft'
      t.integer :rollout_percent, null: false, default: 0
      t.string :min_app_version
      t.integer :security_epoch, null: false, default: 0
      t.text :release_notes
      t.datetime :published_at
      t.string :created_by
      t.timestamps
    end
    add_index :firmware_bundles, %i[hw_rev channel version], unique: true
    add_index :firmware_bundles, %i[hw_rev state]

    create_table :firmware_images do |t|
      t.references :firmware_bundle, null: false, foreign_key: true, index: false
      t.string :component, null: false
      t.string :version, null: false
      t.bigint :size, null: false
      t.string :sha256, null: false
      t.string :signature_key_id, null: false
      t.integer :link_proto
      t.integer :app_proto
      t.string :content_hash
      t.timestamps
    end
    add_index :firmware_images, %i[firmware_bundle_id component], unique: true

    create_table :firmware_reports do |t|
      t.references :firmware_bundle, null: false, foreign_key: true, index: false
      t.integer :user_id
      t.string :device_hash, null: false
      t.string :component
      t.string :from_version
      t.string :to_version
      t.string :result, null: false
      t.string :stage
      t.string :error_code
      t.integer :duration_ms
      t.string :app_version
      t.string :platform
      t.string :phone_model
      t.datetime :created_at, null: false
    end
    add_index :firmware_reports, %i[firmware_bundle_id created_at]
    add_index :firmware_reports, :device_hash
    add_index :firmware_reports, :user_id
    # A deleted account keeps its devices' reports, unlinked.
    add_foreign_key :firmware_reports, :spree_users, column: :user_id, on_delete: :nullify

    create_table :firmware_rate_counters do |t|
      t.string :key, null: false
      t.datetime :window_started_at, null: false
      t.integer :hits, null: false, default: 0
    end
    add_index :firmware_rate_counters, :key, unique: true
    add_index :firmware_rate_counters, :window_started_at
  end
end
