module Beeper
  # glTF visualizers (workspace spec specs/2026-11-15-creator-gltf-visualizers-design.md): a
  # visualizer whose manifest has type "gltf" plays one GLB scene whose parts move with musical
  # features. The contract shared with the app and the web lives in config/schemas/visualizer_gltf
  # (JSON Schema and limits, copied byte for byte from the workspace's specs/gltf-visualizer and
  # pinned by checksum in test/services/beeper/gltf_contract_test.rb).
  #
  #   Beeper::Gltf::Inspector         GLB structure, self-containment, limits, scene summary, stats
  #   Beeper::Gltf::ImageHeader       PNG/JPEG sniffing and header dimensions
  #   Beeper::Gltf::InspectionCache   inspections memoised per blob (a small LRU)
  #   Beeper::Gltf::BindingsSummary   one readable line per binding / rule, for the review page
  #   Beeper::Manifests::VisualizerGltf  the manifest validator (structure, semantics, names, files)
  module Gltf
    SCHEMA_DIR = Rails.root.join('config', 'schemas', 'visualizer_gltf').freeze
    SCHEMA_PATH = SCHEMA_DIR.join('visualizer-gltf.schema.json').freeze
    LIMITS_PATH = SCHEMA_DIR.join('visualizer-gltf.limits.json').freeze

    def self.deep_freeze(value)
      case value
      when Hash then value.each_value { |v| deep_freeze(v) }.freeze
      when Array then value.each { |v| deep_freeze(v) }.freeze
      else value.freeze
      end
    end

    # visualizer-gltf.limits.json, read once (string keys, frozen).
    LIMITS = deep_freeze(JSON.parse(File.read(LIMITS_PATH)))

    # The spec's example (§3: the "dancer example" of manifest-cases.json, abbreviated), shown in
    # the admin's manifest guide. A test validates it against the fixtures' scene summary.
    EXAMPLE_MANIFEST = deep_freeze(
      'format' => 1, 'type' => 'gltf', 'scene' => 'dancer.glb', 'poster' => 'poster.jpg',
      'view' => { 'background' => '#07040F', 'lighting' => 'studio', 'camera' => { 'fov' => 35, 'distance' => 1.2, 'orbitSpeed' => 4 } },
      'materials' => [
        { 'material' => 'Skin', 'toon' => { 'steps' => 3, 'outline' => { 'width' => 0.006, 'color' => '#120A1E' } } },
        { 'material' => '*', 'toon' => { 'steps' => 2 } }
      ],
      'audio' => {
        'schemaVersion' => 1,
        'idle' => { 'clips' => [{ 'clip' => 'Fan', 'timeScale' => 0.5 }] },
        'noteClips' => {
          'initial' => 'Idle', 'fadeMs' => 250, 'priority' => 'velocity', 'onStop' => 'initial', 'returnAfterMs' => 8000,
          'rules' => [
            { 'match' => { 'part' => 'keys', 'notes' => [48, 59] }, 'clip' => 'Dance1', 'mode' => 'loop', 'sync' => 'beat', 'clipBpm' => 120 },
            { 'match' => { 'part' => 'sampler', 'slot' => 15 }, 'clip' => 'Wave', 'mode' => 'once', 'fadeMs' => 120 },
            { 'match' => { 'part' => 'drums', 'voices' => %w[clap rim] }, 'clip' => 'Pump', 'mode' => 'once',
              'velocity' => { 'to' => 'weight', 'range' => [0.5, 1] } }
          ]
        },
        'bindings' => [
          { 'id' => 'kick-thump', 'source' => 'kick', 'outputRange' => [1, 1.25], 'curve' => 'easeOut',
            'smoothing' => { 'attackMs' => 0, 'releaseMs' => 140 },
            'target' => { 'kind' => 'node', 'node' => 'Cone', 'property' => 'scale', 'axis' => 'xyz' } },
          { 'id' => 'bass-glow', 'sources' => [{ 'source' => 'bass', 'weight' => 0.7 }, { 'source' => 'hit', 'weight' => 0.5 }],
            'combine' => 'max', 'outputRange' => [0.5, 6], 'curve' => 'exp', 'smoothing' => { 'attackMs' => 10, 'releaseMs' => 300 },
            'target' => { 'kind' => 'material', 'material' => 'Neon', 'property' => 'emissiveIntensity' } }
        ]
      }
    )

    # model-viewer for the admin's 3D preview: pinned, with its Subresource Integrity hash.
    MODEL_VIEWER_URL = 'https://cdn.jsdelivr.net/npm/@google/model-viewer@4.0.0/dist/model-viewer.min.js'.freeze
    MODEL_VIEWER_INTEGRITY = 'sha384-sr9b4Ux0WhAUGclJ0ym0FSY2zSOMmNSn0bP/SA0e6bNCrpn/5W3QL8mm+LdlQMKw'.freeze

    module_function

    def limits
      LIMITS
    end

    # Whether a digital asset is a glTF visualizer (kind visualizer, manifest type "gltf").
    def visualizer?(asset)
      return false unless asset && asset.kind.to_s == 'visualizer' && asset.manifest.is_a?(Hash)

      asset.manifest['type'] == 'gltf' || asset.manifest[:type] == 'gltf'
    end

    # A number as JavaScript prints it (1 not 1.0), so messages match the TypeScript core.
    def num(value)
      if value.is_a?(Float) && value.finite? && value == value.round && value.abs < 1e21
        value.round.to_s
      else
        value.to_s
      end
    end

    # String(value) in JavaScript, for values read from JSON; absent keys print "undefined".
    def js_string(value, present: true)
      return 'undefined' unless present

      case value
      when nil then 'null'
      when String then value
      when Integer, Float then num(value)
      when true, false then value.to_s
      when Array then value.map { |v| v.nil? ? '' : js_string(v) }.join(',')
      else '[object Object]'
      end
    end

    # Bytes as the TypeScript core prints them ("20.0 MB").
    def mb(bytes)
      format('%.1f MB', bytes.to_f / 1_048_576)
    end
  end
end
