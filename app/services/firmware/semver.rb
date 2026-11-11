module Firmware
  # Semantic versions: MAJOR.MINOR.PATCH, an optional -prerelease and an optional +build. Build
  # metadata is ignored when ordering (as semver says) but kept in the string.
  module Semver
    FORMAT = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/.freeze

    module_function

    def valid?(value)
      value.is_a?(String) && value.length <= 64 && FORMAT.match?(value)
    end

    # A Gem::Version for ordering ("1.2.0-rc.1" < "1.2.0" < "1.10.0"), or nil when not semver.
    def parse(value)
      return unless valid?(value)

      Gem::Version.new(value.split('+', 2).first)
    end

    # -1, 0, 1, or nil when either isn't a version.
    def compare(a, b)
      va = parse(a)
      vb = parse(b)
      return unless va && vb

      va <=> vb
    end
  end
end
