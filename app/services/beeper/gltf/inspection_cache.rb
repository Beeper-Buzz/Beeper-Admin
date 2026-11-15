module Beeper
  module Gltf
    # Inspections of uploaded GLBs, memoised per blob checksum in-process (spec §6.4), so the
    # repeated PATCHes of a draft and the review page don't download a scene of up to 20 MB again.
    # A small LRU: SIZE entries, the least recently used dropped first. Keyed by the blob's MD5 and
    # size (same bytes, same inspection, whichever blob row holds them); a blob without a checksum
    # is not cached.
    module InspectionCache
      SIZE = 4

      @entries = {}
      @lock = Mutex.new

      class << self
        # The cached inspection of blob, or the block's result (stored unless it raises).
        def fetch(blob)
          key = key_for(blob)
          return yield unless key

          hit = @lock.synchronize do
            next nil unless @entries.key?(key)

            @entries[key] = @entries.delete(key) # most recently used last
          end
          return hit if hit

          value = yield
          @lock.synchronize do
            @entries.delete(key)
            @entries[key] = value
            @entries.shift while @entries.size > SIZE
          end
          value
        end

        def key_for(blob)
          checksum = blob.respond_to?(:checksum) ? blob.checksum : nil
          checksum.present? ? "#{checksum}:#{blob.byte_size}" : nil
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
