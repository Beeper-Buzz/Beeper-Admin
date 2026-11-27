# Beeper's admin types for the Spree Admin Native app (spree_admin_native 0.5), on top of the
# generic ones in spree_admin_native_resources.rb (inherited from dna-admin):
# - homepage sections get Beeper's page_key (the homepage or /creators), as in the admin;
# - the Δ8 firmware releases (bundles, images, install reports) under a Firmware group. Writes
#   follow Spree::Admin::FirmwareBundlesController and FirmwareImagesController; FirmwareBundle
#   and FirmwareImage enforce what may change once a bundle is out of draft, and the app is told
#   per record (can.update / can.destroy) so it only offers what they allow.

# Runs now if the inherited type is registered, and again whenever it is (at boot, whichever
# initializer loads first, and after each reload).
if defined?(SpreeAdminNative) && SpreeAdminNative.respond_to?(:resources)
  SpreeAdminNative.resources.configure('homepage_sections') do |r|
    pages = 'HomepageSection::PAGES'.safe_constantize
    r.field :page_key, :enum, options: pages, label: 'Page'
    r.filter :page_key, pages
    r.list :title, :page_key, :section_type, :position, :is_visible
  end
end

Rails.application.config.to_prepare do
  next unless defined?(SpreeAdminNative) && SpreeAdminNative.respond_to?(:resources)

  resources = SpreeAdminNative.resources
  options = ->(constant) { constant.safe_constantize }
  # A bundle's state changes return false with errors on the record; the app shows them per field.
  transition = lambda do |bundle, method, done|
    raise ActiveRecord::RecordInvalid, bundle unless bundle.public_send(method)

    "#{bundle.label} #{done}."
  end

  resources.register 'firmware_bundles' do |r|
    r.model 'FirmwareBundle'
    r.label 'Firmware bundles'
    r.group 'Firmware'
    r.icon 'cpu'
    r.title :label
    r.subtitle :state
    r.list :hw_rev, :version, :channel, :state, :rollout_percent
    r.search :version, :hw_rev
    r.filter :state, options.call('FirmwareBundle::STATES')
    r.filter :channel, options.call('Firmware::CHANNELS')
    r.order :created_at, :desc
    # hw_rev, version and security_epoch only change while the bundle is a draft (FirmwareBundle).
    r.field :hw_rev, :string, label: 'Hardware revision'
    r.field :version, :string
    r.field :channel, :enum, options: options.call('Firmware::CHANNELS')
    r.field :rollout_percent, :integer, label: 'Rollout (%)'
    r.field :min_app_version, :string, label: 'Minimum app version'
    r.field :security_epoch, :integer
    r.field :release_notes, :text
    r.field :state, :enum, options: options.call('FirmwareBundle::STATES'), readonly: true
    r.field :published_at, :datetime, readonly: true
    r.field :created_by, :string, readonly: true
    r.field :created_at
    r.field :updated_at
    # New bundles are drafts (the state column's default), recorded with the admin's email as in
    # the admin's create. Only drafts can be deleted: FirmwareBundle refuses the rest, and the app
    # doesn't offer it. A released bundle stays editable (channel, rollout, minimum app version,
    # notes); FirmwareBundle keeps its hardware revision, version and security epoch.
    r.before_save do |bundle, admin, op|
      next unless op == :create

      bundle.state = 'draft'
      bundle.created_by = admin&.email
    end
    r.deletable_if ->(bundle) { bundle.draft? }
    r.action :publish, label: 'Publish', confirm: 'Publish this bundle? Devices in the rollout are offered it.',
                       if: ->(b) { b.draft? } do |bundle, _admin|
      transition.call(bundle, :publish!, 'published')
    end
    r.action :resume, label: 'Resume', confirm: 'Offer this bundle again?', if: ->(b) { b.paused? } do |bundle, _admin|
      transition.call(bundle, :publish!, 'resumed')
    end
    r.action :pause, label: 'Pause', confirm: 'Stop offering this bundle now? Devices keep what they have.',
                     destructive: true, if: ->(b) { b.published? } do |bundle, _admin|
      transition.call(bundle, :pause!, 'paused: no device is offered it now')
    end
    r.action :revoke, label: 'Revoke', confirm: 'Revoke this bundle? Devices on it are offered the newest good one. This is final.',
                      destructive: true, if: ->(b) { b.published? || b.paused? } do |bundle, _admin|
      transition.call(bundle, :revoke!, 'revoked')
    end
  end

  resources.register 'firmware_images' do |r|
    r.model 'FirmwareImage'
    r.label 'Firmware images'
    r.group 'Firmware'
    r.icon 'memorychip'
    r.title :component
    r.subtitle :version
    r.list :component, :version, :firmware_bundle_id, :size
    r.search :component, :version
    r.filter :component, options.call('Firmware::COMPONENTS')
    r.filter :firmware_bundle_id
    r.order :created_at, :desc
    r.field :firmware_bundle_id, :reference, resource: 'firmware_bundles', label: 'Bundle'
    # The signed image, to download as on the admin's bundle page; never uploaded from the app.
    r.field :file, :file, label: 'Image file', readonly: true
    r.field :component, :string
    r.field :version, :string
    r.field :size, :integer, label: 'Size (bytes)'
    r.field :sha256, :string, label: 'SHA-256'
    r.field :signature_key_id, :string, label: 'Signing key id'
    r.field :link_proto, :integer, label: 'Link protocol'
    r.field :app_proto, :integer, label: 'App protocol'
    r.field :content_hash, :string
    r.field :created_at
    # Images are uploaded (and checked against their sha256 and signature) in the admin or by CI;
    # a draft bundle's image can be removed (FirmwareImage refuses it once the bundle is out).
    r.actions create: false, update: false
    r.deletable_if ->(image) { image.bundle&.draft? }
  end

  resources.register 'firmware_reports' do |r|
    r.model 'FirmwareReport'
    r.label 'Firmware install reports'
    r.group 'Firmware'
    r.icon 'checklist'
    r.title :result
    r.subtitle :to_version
    r.list :result, :firmware_bundle_id, :component, :stage, :created_at
    r.search :device_hash, :error_code
    r.filter :result, options.call('FirmwareReport::RESULTS')
    r.filter :platform, options.call('FirmwareReport::PLATFORMS')
    r.filter :firmware_bundle_id
    r.filter :created_at, :date_range
    r.order :created_at, :desc
    # What the admin's bundle page shows; the reporting user is not.
    r.field :firmware_bundle_id, :reference, resource: 'firmware_bundles', label: 'Bundle'
    r.field :result, :string
    r.field :component, :string
    r.field :stage, :string
    r.field :error_code, :string
    r.field :from_version, :string
    r.field :to_version, :string
    r.field :duration_ms, :integer, label: 'Duration (ms)'
    r.field :platform, :string
    r.field :app_version, :string
    r.field :phone_model, :string
    r.field :device_hash, :string, label: 'Device (hashed)'
    r.field :created_at, :datetime, readonly: true
    # Sent by devices; read only.
    r.actions create: false, update: false, destroy: false
  end
end
