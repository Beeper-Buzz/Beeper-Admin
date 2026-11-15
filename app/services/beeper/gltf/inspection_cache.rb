module Beeper
  module Gltf
    # Inspections of uploaded GLBs, memoised per blob in-process (spec §6.4), so the repeated
    # PATCHes of a draft and the review page don't download a scene of up to 20 MB again. A small
    # LRU: SIZE entries, the least recently used dropped first. Keyed by the blob's storage key,
    # which is unique per blob and whose bytes never change; a blob without a key is not cached.
    # Results that hit a work cap (result.capped) are not stored, so a crafted file can't pin a
    # large error list in memory.
    module InspectionCache
      SIZE = 4

      @entries = {}
      @lock = Mutex.new

      class << self
        # The cached inspection of blob, or the block's result (stored unless it raises or capped).
        def fetch(blob)
          key = key_for(blob)
          return yield unless key

          hit = @lock.synchronize do
            next nil unless @entries.key?(key)

            @entries[key] = @entries.delete(key) # most recently used last
          end
          return hit if hit

          value = yield
          return value if value.respond_to?(:capped) && value.capped

          @lock.synchronize do
            @entries.delete(key)
            @entries[key] = value
            @entries.shift while @entries.size > SIZE
          end
          value
        end

        def key_for(blob)
          key = blob.respond_to?(:key) ? blob.key : nil
          key.present? ? key.to_s : nil
        end

        def size
          @lock.synchronize { @entries.size }
        end

        def clear!
          @lock.synchronize { @entries.clear }
        end
      end
    end
  end
end
