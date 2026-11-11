module Firmware
  # Reads the MCUboot image header and TLV trailer of a radio image, enough to refuse a file that
  # isn't a signed MCUboot image or whose version isn't the declared one. The server never checks
  # the signature itself (it holds no keys; the bootloader verifies), only that one is there.
  #
  # Layout (little-endian; MCUboot docs/design.md, "Image format"):
  #   header  magic u32 = 0x96f3b83d, load_addr u32, hdr_size u16, protect_tlv_size u16,
  #           img_size u32, flags u32, version {major u8, minor u8, revision u16, build u32}
  #   at hdr_size + img_size: [protected TLV info {0x6908, total u16} + TLVs],
  #           TLV info {0x6907, total u16}, then TLVs {type u16, len u16, data}
  class McubootImage
    MAGIC = 0x96f3b83d
    TLV_INFO_MAGIC = 0x6907
    TLV_PROT_INFO_MAGIC = 0x6908
    TLV_ECDSA_SIG = 0x22 # ECDSA P-256 signature
    HEADER_BYTES = 32

    attr_reader :version, :build, :tlv_types, :error

    def self.read(path)
      new(path).tap(&:parse)
    end

    def initialize(path)
      @path = path
      @tlv_types = []
    end

    def valid?
      error.nil?
    end

    def ecdsa_signed?
      tlv_types.include?(TLV_ECDSA_SIG)
    end

    def parse
      File.open(@path, 'rb') do |f|
        size = f.size
        header = f.read(HEADER_BYTES)
        return fail!('is not an MCUboot image (file too short)') if header.nil? || header.bytesize < HEADER_BYTES

        magic, _load, hdr_size, prot_size, img_size, _flags, major, minor, revision, build = header.unpack('VVvvVVCCvV')
        return fail!('is not an MCUboot image (bad magic)') unless magic == MAGIC

        @version = "#{major}.#{minor}.#{revision}"
        @build = build
        offset = hdr_size + img_size
        return fail!('is not an MCUboot image (header sizes exceed the file)') if offset + 4 > size

        if prot_size.positive?
          read_tlv_block(f, offset, TLV_PROT_INFO_MAGIC, size) || return
          offset += prot_size
        end
        read_tlv_block(f, offset, TLV_INFO_MAGIC, size) || return
      end
      self
    end

    private

    def read_tlv_block(file, offset, expected_magic, file_size)
      file.seek(offset)
      info = file.read(4)
      return fail!('has no MCUboot TLV area') if info.nil? || info.bytesize < 4

      magic, total = info.unpack('vv')
      return fail!('has no MCUboot TLV area') unless magic == expected_magic
      return fail!('has a truncated MCUboot TLV area') if offset + total > file_size

      pos = offset + 4
      while pos + 4 <= offset + total
        file.seek(pos)
        type, len = file.read(4).unpack('vv')
        @tlv_types << type
        pos += 4 + len
      end
      true
    end

    def fail!(message)
      @error = message
      nil
    end
  end
end
