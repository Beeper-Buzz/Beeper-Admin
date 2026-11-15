module Beeper
  module Gltf
    # PNG and JPEG headers without decoding: the type from the magic bytes and the pixel size from
    # the PNG IHDR or the first JPEG SOFn. A port of sniffImageMime / imageSize in the shared
    # TypeScript core (specs/gltf-visualizer/ts/glb.ts); keep the two in step.
    #
    # Both read bytes[start, length] in place (getbyte at offsets, no slicing), so the inspector
    # can look at an image inside a 20 MB GLB without copying it.
    module ImageHeader
      PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].freeze
      IHDR = [0x49, 0x48, 0x44, 0x52].freeze
      # Markers a JPEG header scan reads before giving up (MAX_JPEG_MARKERS in glb.ts).
      MAX_JPEG_MARKERS = 512
      NOT_FILL = /[^\xff]/n.freeze
      FILL_RUN = ("\xff".b * 65_536).freeze

      module_function

      # 'image/png' | 'image/jpeg' from the magic bytes, else nil.
      def sniff(bytes, start = 0, length = bytes.bytesize - start)
        if length >= 8 && PNG_SIGNATURE.each_with_index.all? { |b, i| bytes.getbyte(start + i) == b }
          return 'image/png'
        end
        if length >= 3 && bytes.getbyte(start) == 0xff && bytes.getbyte(start + 1) == 0xd8 && bytes.getbyte(start + 2) == 0xff
          return 'image/jpeg'
        end

        nil
      end

      # { width:, height: } from the header, or nil when the bytes don't match mime or the header
      # can't be read.
      def size(bytes, mime, start = 0, length = bytes.bytesize - start)
        return nil unless sniff(bytes, start, length) == mime

        bytes = bytes.b unless bytes.encoding == Encoding::BINARY # the inspector passes binary already

        case mime
        when 'image/png' then png_size(bytes, start, length)
        when 'image/jpeg' then jpeg_size(bytes, start, length)
        end
      end

      def u32be(bytes, offset)
        (bytes.getbyte(offset) << 24) | (bytes.getbyte(offset + 1) << 16) | (bytes.getbyte(offset + 2) << 8) | bytes.getbyte(offset + 3)
      end

      # Signature (8), then the IHDR chunk: length (4), "IHDR", width (4, BE), height (4, BE).
      def png_size(bytes, start, length)
        return nil if length < 24 || IHDR.each_with_index.any? { |b, i| bytes.getbyte(start + 12 + i) != b }

        width = u32be(bytes, start + 16)
        height = u32be(bytes, start + 20)
        width.positive? && height.positive? ? { width: width, height: height } : nil
      end

      def jpeg_sof?(marker)
        (0xc0..0xc3).cover?(marker) || (0xc5..0xc7).cover?(marker) || (0xc9..0xcb).cover?(marker) ||
          (0xcd..0xcf).cover?(marker)
      end

      # The first index in bytes[from...to] whose byte isn't 0xFF, or nil. Whole 64 KB chunks are
      # compared with a run of 0xFF (memcmp); only a chunk that differs is searched byte-wise.
      def first_not_fill(bytes, from, to)
        while from < to
          length = [FILL_RUN.bytesize, to - from].min
          chunk = bytes.byteslice(from, length)
          unless length == FILL_RUN.bytesize && chunk == FILL_RUN
            found = chunk.index(NOT_FILL)
            return from + found if found
          end
          from += length
        end
        nil
      end

      # Offsets i are relative to start; n is the image's length.
      def jpeg_size(bytes, start, n)
        at = ->(i) { bytes.getbyte(start + i) }
        i = 2
        markers = 0
        while i + 1 < n
          return nil if at.call(i) != 0xff

          markers += 1
          return nil if markers > MAX_JPEG_MARKERS # a crafted marker chain can't run long

          marker = at.call(i + 1)
          if marker == 0xff && i + 2 < n
            # Fill bytes: glb.ts steps i while bytes[i + 1] is 0xFF and i + 2 < n, ending on the
            # first other byte or the last one. The same stop, found a chunk at a time (C speed),
            # so views overlapping one long 0xFF run can't cost a Ruby loop iteration per byte.
            other = first_not_fill(bytes, start + i + 1, start + n - 1)
            stop = other.nil? ? n - 1 : other - start
            i = stop - 1
            marker = at.call(i + 1)
          end
          i += 2
          next if marker == 0xd8 || marker == 0x01 || (0xd0..0xd7).cover?(marker) # no length field
          return nil if marker == 0xd9 || marker == 0xda # end of image / scan data before any SOF
          return nil if i + 2 > n

          segment = (at.call(i) << 8) | at.call(i + 1)
          return nil if segment < 2

          if jpeg_sof?(marker)
            return nil if i + 7 > n

            height = (at.call(i + 3) << 8) | at.call(i + 4)
            width = (at.call(i + 5) << 8) | at.call(i + 6)
            return width.positive? && height.positive? ? { width: width, height: height } : nil
          end
          i += segment
        end
        nil
      end
    end
  end
end
