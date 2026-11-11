module Firmware
  # Adds an image file to a draft bundle: hashes the local file, validates the image against it
  # (declared sha256 and size, MCUboot header for radio images), then uploads the blob to storage
  # and saves. The blob is uploaded before the row is saved (as AppFeedback screenshots are), so a
  # storage error leaves no row; a blob whose row then fails to save is purged.
  #
  #   image = Firmware::ImageUpload.call(bundle, path, component: 'stm32', version: '1.4.0', ...)
  #   image.persisted? # false => image.errors
  module ImageUpload
    ATTRIBUTES = %i[component version size sha256 signature_key_id link_proto app_proto content_hash].freeze

    module_function

    def call(bundle, path, attributes)
      image = bundle.images.build(attributes.to_h.symbolize_keys.slice(*ATTRIBUTES))
      image.stage_file(path)
      unless image.valid?
        bundle.images.delete(image)
        return image
      end

      key = ActiveStorage::Blob.generate_unique_secure_token
      begin
        File.open(path, 'rb') do |io|
          blob = ActiveStorage::Blob.create_and_upload!(key: key, io: io, filename: image.download_filename,
                                                        content_type: 'application/octet-stream', identify: false)
          image.file.attach(blob)
        end
        image.save!
      rescue StandardError => e
        Rails.logger.error("[firmware] image upload failed: #{e.class}: #{e.message}")
        discard(key)
        image.errors.add(:file, 'could not be stored') unless image.errors.any?
        bundle.images.delete(image) unless image.persisted?
      end
      image
    end

    def discard(key)
      blob = ActiveStorage::Blob.find_by(key: key)
      blob ? blob.purge : ActiveStorage::Blob.service.delete(key)
    rescue StandardError => e
      Rails.logger.error("[firmware] discarding an unsaved image blob failed: #{e.class}")
    end
  end
end
