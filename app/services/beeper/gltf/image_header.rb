module Beeper
  module Gltf
    # PNG and JPEG headers without decoding: the type from the magic bytes and the pixel size from
    # the PNG IHDR or the first JPEG SOFn. A port of sniffImageMime / imageSize in the shared
    # TypeScript core (specs/gltf-visualizer/ts/glb.ts); keep the two in step.
    module ImageHeader
      PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].freeze

      module_function

      # 'image/png' | 'image/jpeg' from the magic bytes, else nil.
      def sniff(bytes)
        return 'image/png' if bytes.bytesize >= 8 && PNG_SIGNATURE.each_with_index.all? { |b, i| bytes.getbyte(i) == b }
        return 'image/jpeg' if bytes.bytesize >= 3 && bytes.getbyte(0) == 0xff && bytes.getbyte(1) == 0xd8 && bytes.getbyte(2) == 0xff

        nil
      end

      # { width:, height: } from the header, or nil when the bytes don't match mime or the header
      # can't be read.
      def size(bytes, mime)
        return nil unless sniff(bytes) == mime

        case mime
        when 'image/png' then png_size(bytes)
        when 'image/jpeg' then jpeg_size(bytes)
        end
      end

      # Signature (8), then the IHDR chunk: length (4), "IHDR", width (4, BE), height (4, BE).
      def png_size(bytes)
        return nil if bytes.bytesize < 24 || bytes.byteslice(12, 4) != 'IHDR'.b

        width, height = bytes.byteslice(16, 8).unpack('NN')
        width.positive? && height.positive? ? { width: width, height: height } : nil
      end

      def jpeg_sof?(marker)
        (0xc0..0xc3).cover?(marker) || (0xc5..0xc7).cover?(marker) || (0xc9..0xcb).cover?(marker) ||
          (0xcd..0xcf).cover?(marker)
      end

      def jpeg_size(bytes)
        n = bytes.bytesize
        i = 2
        while i + 1 < n
          return nil if bytes.getbyte(i) != 0xff

          marker = bytes.getbyte(i + 1)
          while marker == 0xff && i + 2 < n # fill bytes
            i += 1
            marker = bytes.getbyte(i + 1)
          end
          i += 2
          next if marker == 0xd8 || marker == 0x01 || (0xd0..0xd7).cover?(marker) # no length field
          return nil if [0xd9, 0xda].include?(marker) # end of image / scan data before any SOF
          return nil if i + 2 > n

          length = (bytes.getbyte(i) << 8) | bytes.getbyte(i + 1)
          return nil if length < 2

          if jpeg_sof?(marker)
            return nil if i + 7 > n

            height = (bytes.getbyte(i + 3) << 8) | bytes.getbyte(i + 4)
            width = (bytes.getbyte(i + 5) << 8) | bytes.getbyte(i + 6)
            return width.positive? && height.positive? ? { width: width, height: height } : nil
          end
          i += length
        end
        nil
      end
    end
  end
end
