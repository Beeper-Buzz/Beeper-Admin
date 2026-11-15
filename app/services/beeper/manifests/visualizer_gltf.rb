module Beeper
  module Manifests
    # visualizer, type "gltf" (spec §2, §4, §6): one attached GLB scene, an optional poster, and a
    # declarative audio config (bindings, idle clips, note → clip rules), toon material overrides
    # and a view. Beeper::Manifests::Visualizer dispatches here on manifest["type"] == "gltf".
    #
    # .call(manifest, asset = nil) -> ["<path>: <message>", ...]
    #   1. structure (visualizer-gltf.schema.json by hand, unknown keys rejected everywhere) and the
    #      semantic rules (bounds per target, one owner per clip, each target bound once...): a port
    #      of validateManifest in the shared TypeScript core (specs/gltf-visualizer/ts/manifest.ts),
    #      same paths, same messages;
    #   2. with an asset, its files: the scene attached and a .glb of at most 20 MB (refused by
    #      byte_size before any download), the poster (optional) attached, a PNG, JPEG or WebP of
    #      at most 2 MB, no other file;
    #   3. the scene downloaded and inspected (Beeper::Gltf::Inspector, memoised per blob checksum
    #      by Beeper::Gltf::InspectionCache), its errors added, and the manifest's names resolved
    #      against its summary, with outlines counted toward the draw calls.
    # Without an asset, steps 2 and 3 are skipped (as for the other kinds).
    #
    # .validate(manifest, summary, limits:, stats:) is step 1 (+ names when a summary is given):
    # the port of validateManifest itself, used by the fixture tests.
    module VisualizerGltf
      SOURCE_NAMES = %w[bass mid high level beat onset beatPhase barPhase bpm playing notePulse note noteHz
                        hit drums sampler synth kick snare hats].freeze
      DRUM_VOICES = %w[kick snare closed-hat open-hat clap low-tom high-tom rim mid-tom].freeze
      CURVES = %w[linear easeIn easeOut easeInOut exp step].freeze
      COMBINE_MODES = %w[sum max avg mul].freeze
      CLIP_MODES = %w[speed weight scrub play trigger].freeze
      NODE_PROPERTIES = %w[position rotation scale spin].freeze
      AXES = %w[x y z xyz].freeze
      MATERIAL_PROPERTIES = %w[emissiveIntensity emissiveColor color hueShift opacity roughness metalness].freeze
      CAMERA_PROPERTIES = %w[orbitSpeed dolly].freeze
      TARGET_KINDS = %w[clip morph node material light camera].freeze
      DEFAULT_AXIS = { 'position' => 'y', 'rotation' => 'y', 'scale' => 'xyz', 'spin' => 'y' }.freeze

      GLB = %r{\A[^\\/]+\.[gG][lL][bB]\z}.freeze
      POSTER = %r{\A[^\\/]+\.([pP][nN][gG]|[jJ][pP][eE]?[gG]|[wW][eE][bB][pP])\z}.freeze
      HEX = /\A#[0-9a-fA-F]{6}\z/.freeze
      ID = /\A[A-Za-z0-9_-]{1,32}\z/.freeze
      POSTER_TYPES = %w[image/png image/jpeg image/webp].freeze

      TOP_KEYS = %w[format type scene poster view materials audio files].freeze
      VIEW_KEYS = %w[background lighting exposure camera].freeze
      CAMERA_KEYS = %w[node fov distance elevation azimuth orbitSpeed].freeze
      FRAMING_KEYS = %w[fov distance elevation azimuth].freeze
      AUDIO_KEYS = %w[schemaVersion idle bindings noteClips].freeze
      BINDING_KEYS = %w[id source sources combine inputRange outputRange curve steps smoothing invert target].freeze
      TARGET_KEYS = {
        'clip' => [%w[kind clip mode threshold fadeMs], %w[kind clip mode]],
        'morph' => [%w[kind mesh morph], %w[kind mesh morph]],
        'node' => [%w[kind node property axis], %w[kind node property]],
        'material' => [%w[kind material property colors], %w[kind material property]],
        'light' => [%w[kind light property], %w[kind light property]],
        'camera' => [%w[kind property], %w[kind property]]
      }.freeze
      NOTE_CLIPS_KEYS = %w[initial fadeMs priority onStop returnAfterMs rules].freeze
      RULE_KEYS = %w[match clip mode sync fadeMs timeScale clipBpm velocity].freeze
      KIND_WORD = { 'clip' => 'animation', 'node' => 'node', 'mesh' => 'mesh', 'material' => 'material',
                    'light' => 'node', 'camera' => 'node' }.freeze

      module_function

      def call(manifest, asset = nil)
        return ['manifest: must be an object'] unless manifest.is_a?(Hash)

        manifest = manifest.deep_stringify_keys
        files = Manifests.attached(asset)
        return validate(manifest, nil) unless files

        file_errors, inspection = check_files(manifest, files)
        errors = validate(manifest, inspection&.summary, stats: inspection&.stats)
        errors.concat(file_errors)
        errors.concat(inspection.errors) if inspection
        errors
      end

      # The port of validateManifest: structure and semantics, and names when summary is given
      # (with stats, outlines count toward the draw calls).
      def validate(manifest, summary, limits: Beeper::Gltf::LIMITS, stats: nil)
        c = Checker.new(limits)
        return ['manifest: must be an object'] unless c.object(manifest, '', TOP_KEYS, %w[format type scene audio])

        m = manifest
        c.err('format', 'must be 1') if m.key?('format') && !(Manifests.number?(m['format']) && m['format'] == 1)
        c.err('type', 'must be "gltf"') if m.key?('type') && m['type'] != 'gltf'
        c.pattern(m['scene'], 'scene', GLB, 255, 'a .glb file name without a directory') if m.key?('scene')
        c.pattern(m['poster'], 'poster', POSTER, 255, 'a .png, .jpg or .webp file name without a directory') if m.key?('poster')
        check_view(c, m['view']) if m.key?('view')
        check_materials(c, m['materials']) if m.key?('materials')
        check_audio(c, m['audio']) if m.key?('audio')
        if summary
          check_names(c, summary)
          check_draw_calls(c, m['materials'], summary, stats) if stats
        end
        c.errors
      end

      # The scene's inspection (memoised per blob checksum), or nil when it can't be read.
      def inspection(blob)
        Beeper::Gltf::InspectionCache.fetch(blob) do
          Beeper::Gltf::Inspector.call(blob.download)
        end
      rescue StandardError => e
        Rails.logger.warn("[gltf] could not inspect blob #{blob&.id}: #{e.class}: #{e.message}")
        nil
      end

      # Draw calls the runtime issues: primitives × instances, outlined primitives twice (§4.7).
      def draw_calls(manifest, summary, stats)
        stats['drawCalls'] + outline_draw_calls(manifest.is_a?(Hash) ? manifest['materials'] : nil, summary, stats)
      end

      # --- files ------------------------------------------------------------------------------------

      # [errors, inspection or nil] for the attached files.
      def check_files(manifest, files)
        limits = Beeper::Gltf::LIMITS
        errors = []
        result = nil
        scene = manifest['scene']
        poster = manifest['poster']
        if scene.is_a?(String) && scene.match?(GLB)
          blob = files[scene]
          if blob.nil?
            errors << %(scene: "#{scene}" is not attached)
          elsif blob.byte_size.to_i > limits['glbMaxBytes']
            errors << "scene: the file is #{Beeper::Gltf.mb(blob.byte_size)}; the limit is #{Beeper::Gltf.mb(limits['glbMaxBytes'])}"
          else
            result = inspection(blob)
            errors << %(scene: "#{scene}" could not be read) unless result
          end
        end
        if poster.is_a?(String) && poster.match?(POSTER)
          blob = files[poster]
          if blob.nil?
            errors << %(poster: "#{poster}" is not attached)
          elsif blob.byte_size.to_i > limits['posterMaxBytes']
            errors << "poster: the file is #{Beeper::Gltf.mb(blob.byte_size)}; the limit is #{Beeper::Gltf.mb(limits['posterMaxBytes'])}"
          elsif !POSTER_TYPES.include?(blob.content_type.to_s.downcase)
            errors << "poster: must be a PNG, JPEG or WebP image (the upload is #{blob.content_type.presence || 'untyped'})"
          end
        end
        named = [scene, poster].select { |name| name.is_a?(String) }
        (files.keys - named).sort.each do |name|
          errors << %(files: "#{name}" is not named by the manifest; a glTF visualizer holds only its scene (.glb) and an optional poster)
        end
        [errors, result]
      end

      # --- structure and semantics ------------------------------------------------------------------

      def check_view(c, v)
        return unless c.object(v, 'view', VIEW_KEYS, [])

        c.color(v['background'], 'view.background') if v.key?('background')
        c.one_of(v['lighting'], 'view.lighting', %w[studio scene]) if v.key?('lighting')
        c.num(v['exposure'], 'view.exposure', 0.25, 4) if v.key?('exposure')
        return unless v.key?('camera')

        cam = v['camera']
        return unless c.object(cam, 'view.camera', CAMERA_KEYS, [])

        c.ref('camera', cam['node'], 'view.camera.node') if cam.key?('node') && c.name(cam['node'], 'view.camera.node')
        c.num(cam['fov'], 'view.camera.fov', 20, 90) if cam.key?('fov')
        c.num(cam['distance'], 'view.camera.distance', 0.5, 10) if cam.key?('distance')
        c.num(cam['elevation'], 'view.camera.elevation', -80, 80) if cam.key?('elevation')
        c.num(cam['azimuth'], 'view.camera.azimuth', -180, 180) if cam.key?('azimuth')
        c.num(cam['orbitSpeed'], 'view.camera.orbitSpeed', -90, 90) if cam.key?('orbitSpeed')
        return unless cam.key?('node')

        FRAMING_KEYS.each do |k|
          c.err("view.camera.#{k}", 'not allowed with camera.node (the glTF camera frames the scene)') if cam.key?(k)
        end
      end

      def check_materials(c, v)
        return unless c.array(v, 'materials', 0, c.limits['maxMaterialOverrides'])

        seen = {}
        v.each_with_index do |m, i|
          path = "materials[#{i}]"
          next unless c.object(m, path, %w[material toon], %w[material toon])

          if m.key?('material') && c.name(m['material'], "#{path}.material")
            name = m['material']
            if seen.key?(name)
              c.err("#{path}.material", name == '*' ? '"*" may appear only once' : %("#{name}" already has an override (materials[#{seen[name]}])))
            else
              seen[name] = i
              c.ref('material', name, "#{path}.material") unless name == '*'
            end
          end
          next unless m.key?('toon')

          toon = m['toon']
          next unless c.object(toon, "#{path}.toon", %w[steps outline], %w[steps])

          c.num(toon['steps'], "#{path}.toon.steps", 2, 8, integer: true) if toon.key?('steps')
          next unless toon.key?('outline')

          outline = toon['outline']
          next unless c.object(outline, "#{path}.toon.outline", %w[width color], %w[width])

          c.num(outline['width'], "#{path}.toon.outline.width", 0.001, 0.05) if outline.key?('width')
          c.color(outline['color'], "#{path}.toon.outline.color") if outline.key?('color')
        end
      end

      # The limits key of a target, or nil (play/trigger, or an unknown shape).
      def output_key(target)
        return nil unless target.is_a?(Hash)

        case target['kind']
        when 'clip' then %w[speed weight scrub].include?(target['mode']) ? "clip.#{target['mode']}" : nil
        when 'morph' then 'morph'
        when 'node' then NODE_PROPERTIES.include?(target['property']) ? "node.#{target['property']}" : nil
        when 'material' then MATERIAL_PROPERTIES.include?(target['property']) ? "material.#{target['property']}" : nil
        when 'light' then 'light.intensity'
        when 'camera' then CAMERA_PROPERTIES.include?(target['property']) ? "camera.#{target['property']}" : nil
        end
      end

      # Checks a target; returns { key:, mode:, output_key: } (key: its identity for the duplicate
      # rule, nil when it can't be keyed or adds up), or nil when it is not even a known kind.
      def check_target(c, t, path, clip_uses, index)
        unless t.is_a?(Hash)
          c.err(path, 'must be an object')
          return nil
        end
        return nil unless c.one_of(t['kind'], "#{path}.kind", TARGET_KINDS)

        kind = t['kind']
        allowed, required = TARGET_KEYS.fetch(kind)
        return nil unless c.object(t, path, allowed, required)

        key = nil
        mode = nil
        case kind
        when 'clip'
          ok_clip = t.key?('clip') && c.name(t['clip'], "#{path}.clip")
          ok_mode = t.key?('mode') && c.one_of(t['mode'], "#{path}.mode", CLIP_MODES)
          if t.key?('threshold') && c.num(t['threshold'], "#{path}.threshold", 0.01, 1) && ok_mode && !%w[play trigger].include?(t['mode'])
            c.err("#{path}.threshold", 'only on play or trigger clip targets')
          end
          c.num(t['fadeMs'], "#{path}.fadeMs", 0, 5000) if t.key?('fadeMs')
          c.ref('clip', t['clip'], "#{path}.clip") if ok_clip
          if ok_clip && ok_mode
            mode = t['mode']
            key = "clip\u0000#{t['clip']}\u0000#{mode}"
            clip_uses << { clip: t['clip'], mode: mode, index: index }
          end
        when 'morph'
          ok_mesh = t.key?('mesh') && c.name(t['mesh'], "#{path}.mesh")
          ok_morph = false
          if t.key?('morph')
            ok_morph = t['morph'].is_a?(String) ? c.name(t['morph'], "#{path}.morph") : c.num(t['morph'], "#{path}.morph", 0, 31, integer: true)
          end
          c.ref('mesh', t['mesh'], "#{path}.mesh") if ok_mesh
          if ok_mesh && ok_morph
            c.morphs << { mesh: t['mesh'], morph: t['morph'], path: "#{path}.morph" }
            type = t['morph'].is_a?(String) ? 'string' : 'number'
            key = "morph\u0000#{t['mesh']}\u0000#{type}\u0000#{Beeper::Gltf.js_string(t['morph'])}"
          end
        when 'node'
          c.ref('node', t['node'], "#{path}.node") if t.key?('node') && c.name(t['node'], "#{path}.node")
          c.one_of(t['property'], "#{path}.property", NODE_PROPERTIES) if t.key?('property')
          c.one_of(t['axis'], "#{path}.axis", AXES) if t.key?('axis')
          # node targets add up: no identity
        when 'material'
          ok_mat = t.key?('material') && c.name(t['material'], "#{path}.material")
          ok_prop = t.key?('property') && c.one_of(t['property'], "#{path}.property", MATERIAL_PROPERTIES)
          ok_colors = true
          if t.key?('colors')
            if !t['colors'].is_a?(Array) || t['colors'].size != 2
              c.err("#{path}.colors", 'must be an array of 2 colours')
              ok_colors = false
            else
              2.times { |i| ok_colors = c.color(t['colors'][i], "#{path}.colors[#{i}]") && ok_colors }
            end
          end
          if ok_prop && ok_colors
            needs = %w[color emissiveColor].include?(t['property'])
            if needs && !t.key?('colors')
              c.err("#{path}.colors", "required for #{t['property']} (the two colours to blend between)")
            end
            c.err("#{path}.colors", "only for color and emissiveColor, not #{t['property']}") if !needs && t.key?('colors')
          end
          c.ref('material', t['material'], "#{path}.material") if ok_mat
          key = "material\u0000#{t['material']}\u0000#{t['property']}" if ok_mat && ok_prop
        when 'light'
          ok_light = t.key?('light') && c.name(t['light'], "#{path}.light")
          c.err("#{path}.property", 'must be "intensity"') if t.key?('property') && t['property'] != 'intensity'
          if ok_light
            c.ref('light', t['light'], "#{path}.light")
            key = "light\u0000#{t['light']}"
          end
        when 'camera'
          key = "camera\u0000#{t['property']}" if t.key?('property') && c.one_of(t['property'], "#{path}.property", CAMERA_PROPERTIES)
        end
        { key: key, mode: mode, output_key: output_key(t) }
      end

      def check_binding(c, b, path, clip_uses, index)
        return nil unless c.object(b, path, BINDING_KEYS, %w[target])

        c.pattern(b['id'], "#{path}.id", ID, 32, '1 to 32 letters, digits, _ or -') if b.key?('id')

        # source XOR sources; combine only with sources
        if b.key?('source') && b.key?('sources')
          c.err(path, 'give source or sources, not both')
        elsif !b.key?('source') && !b.key?('sources')
          c.err(path, 'needs source or sources')
        end
        c.err("#{path}.combine", 'only with sources') if b.key?('combine') && !b.key?('sources')
        c.one_of(b['source'], "#{path}.source", SOURCE_NAMES) if b.key?('source')
        if b.key?('sources') && c.array(b['sources'], "#{path}.sources", 1, c.limits['maxSourcesPerBinding'])
          b['sources'].each_with_index do |s, i|
            sp = "#{path}.sources[#{i}]"
            next unless c.object(s, sp, %w[source weight], %w[source])

            c.one_of(s['source'], "#{sp}.source", SOURCE_NAMES) if s.key?('source')
            c.num(s['weight'], "#{sp}.weight", -4, 4) if s.key?('weight')
          end
        end
        c.one_of(b['combine'], "#{path}.combine", COMBINE_MODES) if b.key?('combine')

        if b.key?('inputRange') && c.pair(b['inputRange'], "#{path}.inputRange") && b['inputRange'][0] == b['inputRange'][1]
          c.err("#{path}.inputRange", 'the two ends must differ')
        end
        ok_out = b.key?('outputRange') && c.pair(b['outputRange'], "#{path}.outputRange")
        ok_curve = b.key?('curve') && c.one_of(b['curve'], "#{path}.curve", CURVES)
        if b.key?('steps') && c.num(b['steps'], "#{path}.steps", 2, 16, integer: true) && !(ok_curve && b['curve'] == 'step')
          c.err("#{path}.steps", 'only with curve "step"')
        end
        if b.key?('smoothing')
          s = b['smoothing']
          if c.object(s, "#{path}.smoothing", %w[attackMs releaseMs], [])
            c.num(s['attackMs'], "#{path}.smoothing.attackMs", 0, 5000) if s.key?('attackMs')
            c.num(s['releaseMs'], "#{path}.smoothing.releaseMs", 0, 5000) if s.key?('releaseMs')
          end
        end
        c.bool(b['invert'], "#{path}.invert") if b.key?('invert')

        return nil unless b.key?('target')

        t = check_target(c, b['target'], "#{path}.target", clip_uses, index)
        return nil unless t

        if ok_out
          range = b['outputRange']
          if %w[play trigger].include?(t[:mode])
            c.err("#{path}.outputRange", "not allowed on a #{t[:mode]} clip target (it follows the threshold)")
          elsif t[:output_key]
            low, high = c.limits['outputBounds'].fetch(t[:output_key])
            unless range.all? { |x| x >= low && x <= high }
              c.err("#{path}.outputRange", "must stay within #{Beeper::Gltf.num(low)}..#{Beeper::Gltf.num(high)} for #{t[:output_key]}")
            end
          end
        end
        t[:key]
      end

      def check_match(c, m, path)
        unless m.is_a?(Hash)
          c.err(path, 'must be an object')
          return
        end
        unless m.key?('part')
          c.err("#{path}.part", 'required')
          return
        end
        part = m['part']
        one, many = case part
                    when 'synth', 'samplerKeys', 'keys' then %w[note notes]
                    when 'sampler' then %w[slot slots]
                    when 'drums' then %w[voice voices]
                    end
        unless one
          c.err("#{path}.part", 'must be one of "synth", "samplerKeys", "keys", "sampler", "drums"')
          return
        end
        return unless c.object(m, path, ['part', one, many], %w[part])

        if m.key?(one) && m.key?(many)
          c.err(path, "give #{one} or #{many}, not both")
        elsif !m.key?(one) && !m.key?(many)
          c.err(path, "needs #{one} or #{many}")
        end
        if part == 'drums'
          c.one_of(m['voice'], "#{path}.voice", DRUM_VOICES) if m.key?('voice')
          if m.key?('voices') && c.array(m['voices'], "#{path}.voices", 1, DRUM_VOICES.size)
            voices = m['voices']
            voices.each_with_index do |voice, i|
              if c.one_of(voice, "#{path}.voices[#{i}]", DRUM_VOICES) && voices.index(voice) != i
                c.err("#{path}.voices[#{i}]", 'listed twice')
              end
            end
          end
          return
        end
        max = part == 'sampler' ? 15 : 127
        c.num(m[one], "#{path}.#{one}", 0, max, integer: true) if m.key?(one)
        return unless m.key?(many)

        range = m[many]
        if c.pair(range, "#{path}.#{many}") { |x, p| c.num(x, p, 0, max, integer: true) } && range[0] > range[1]
          c.err("#{path}.#{many}", 'the first must not exceed the second')
        end
      end

      def check_note_clips(c, nc, path)
        return unless c.object(nc, path, NOTE_CLIPS_KEYS, %w[initial rules])

        c.ref('clip', nc['initial'], "#{path}.initial") if nc.key?('initial') && c.name(nc['initial'], "#{path}.initial")
        c.num(nc['fadeMs'], "#{path}.fadeMs", 0, 5000) if nc.key?('fadeMs')
        c.one_of(nc['priority'], "#{path}.priority", %w[last velocity]) if nc.key?('priority')
        c.one_of(nc['onStop'], "#{path}.onStop", %w[hold initial]) if nc.key?('onStop')
        c.num(nc['returnAfterMs'], "#{path}.returnAfterMs", 0, 60_000) if nc.key?('returnAfterMs')
        return unless nc.key?('rules') && c.array(nc['rules'], "#{path}.rules", 1, c.limits['maxNoteClipRules'])

        nc['rules'].each_with_index do |r, i|
          rp = "#{path}.rules[#{i}]"
          next unless c.object(r, rp, RULE_KEYS, %w[match clip])

          check_match(c, r['match'], "#{rp}.match") if r.key?('match')
          c.ref('clip', r['clip'], "#{rp}.clip") if r.key?('clip') && c.name(r['clip'], "#{rp}.clip")
          c.one_of(r['mode'], "#{rp}.mode", %w[loop once]) if r.key?('mode')
          c.one_of(r['sync'], "#{rp}.sync", %w[now beat bar]) if r.key?('sync')
          c.num(r['fadeMs'], "#{rp}.fadeMs", 0, 5000) if r.key?('fadeMs')
          c.num(r['timeScale'], "#{rp}.timeScale", 0.1, 4) if r.key?('timeScale')
          c.num(r['clipBpm'], "#{rp}.clipBpm", 20, 300) if r.key?('clipBpm')
          next unless r.key?('velocity')

          v = r['velocity']
          vp = "#{rp}.velocity"
          next unless c.object(v, vp, %w[to range], %w[to range])

          ok_to = v.key?('to') && c.one_of(v['to'], "#{vp}.to", %w[weight timeScale])
          next unless v.key?('range') && c.pair(v['range'], "#{vp}.range") && ok_to

          low, high = c.limits['velocityBounds'].fetch(v['to'])
          unless v['range'].all? { |x| x >= low && x <= high }
            c.err("#{vp}.range", "must stay within #{Beeper::Gltf.num(low)}..#{Beeper::Gltf.num(high)} for #{v['to']}")
          end
        end
      end

      def check_audio(c, a)
        return unless c.object(a, 'audio', AUDIO_KEYS, %w[schemaVersion])

        c.err('audio.schemaVersion', 'must be 1') if a.key?('schemaVersion') && !(Manifests.number?(a['schemaVersion']) && a['schemaVersion'] == 1)

        # One owner per clip: idle, then noteClips, then bindings; the later claimant gets the error.
        idle_clips = []
        note_clip_names = []
        if a.key?('idle')
          idle = a['idle']
          if c.object(idle, 'audio.idle', %w[clips], %w[clips]) && idle.key?('clips') &&
             c.array(idle['clips'], 'audio.idle.clips', 1, c.limits['maxIdleClips'])
            idle['clips'].each_with_index do |e, i|
              p = "audio.idle.clips[#{i}]"
              next unless c.object(e, p, %w[clip timeScale], %w[clip])

              if e.key?('clip') && c.name(e['clip'], "#{p}.clip")
                c.ref('clip', e['clip'], "#{p}.clip")
                idle_clips << e['clip']
              end
              c.num(e['timeScale'], "#{p}.timeScale", 0.1, 4) if e.key?('timeScale')
            end
          end
        end
        if a.key?('noteClips')
          check_note_clips(c, a['noteClips'], 'audio.noteClips')
          nc = a['noteClips']
          if nc.is_a?(Hash)
            claim = lambda do |name, path|
              next unless name.is_a?(String)

              if idle_clips.include?(name)
                c.err(path, %("#{name}" is already driven by audio.idle; a clip has one owner))
              else
                note_clip_names << name
              end
            end
            claim.call(nc['initial'], 'audio.noteClips.initial')
            if nc['rules'].is_a?(Array)
              nc['rules'].each_with_index { |r, i| claim.call(r['clip'], "audio.noteClips.rules[#{i}].clip") if r.is_a?(Hash) }
            end
          end
        end
        return unless a.key?('bindings') && c.array(a['bindings'], 'audio.bindings', 0, c.limits['maxBindings'])

        clip_uses = []
        identities = {}
        a['bindings'].each_with_index do |binding, i|
          path = "audio.bindings[#{i}]"
          key = check_binding(c, binding, path, clip_uses, i)
          next if key.nil?

          if identities.key?(key)
            c.err("#{path}.target", "the same target as audio.bindings[#{identities[key]}]; each target may be bound once (node targets excepted)")
          else
            identities[key] = i
          end
        end
        # Clip bindings: not on idle / noteClips clips; on one clip only speed + weight combine.
        clip_uses.each_with_index do |use, u|
          path = "audio.bindings[#{use[:index]}].target"
          if idle_clips.include?(use[:clip])
            c.err("#{path}.clip", %("#{use[:clip]}" is already driven by audio.idle; a clip has one owner))
            next
          end
          if note_clip_names.include?(use[:clip])
            c.err("#{path}.clip", %("#{use[:clip]}" is already driven by audio.noteClips; a clip has one owner))
            next
          end
          clip_uses.first(u).each do |prev|
            next if prev[:clip] != use[:clip] || prev[:mode] == use[:mode] # same mode: the duplicate rule reports it

            combinable = %w[speed weight].include?(prev[:mode]) && %w[speed weight].include?(use[:mode])
            next if combinable

            c.err("#{path}.mode", %("#{use[:clip]}" already has a #{prev[:mode]} binding (audio.bindings[#{prev[:index]}]); only speed and weight combine on one clip))
            break
          end
        end
      end

      # --- names against the scene summary ----------------------------------------------------------

      def check_names(c, s)
        mesh_names = s['meshes'].map { |m| m['name'] }
        clip_names = s['animations'].map { |a| a['name'] }
        lists = { 'clip' => clip_names, 'mesh' => mesh_names, 'material' => s['materials'] }
        c.refs.each do |r|
          n = lists.fetch(r[:kind], s['nodes']).count(r[:name])
          word = KIND_WORD.fetch(r[:kind])
          if n.zero?
            c.err(r[:path], %("#{r[:name]}" is not #{word == 'animation' ? 'an' : 'a'} #{word} in the scene))
          elsif n > 1
            c.err(r[:path], %("#{r[:name]}" names #{n} #{word}s in the scene; rename them so it is unique))
          elsif r[:kind] == 'light' && !s['lights'].include?(r[:name])
            c.err(r[:path], %(node "#{r[:name]}" carries no KHR_lights_punctual light))
          elsif r[:kind] == 'camera' && !s['cameras'].include?(r[:name])
            c.err(r[:path], %(node "#{r[:name]}" carries no camera))
          end
        end
        c.morphs.each do |m|
          next if mesh_names.count(m[:mesh]) != 1 # the mesh error covers it

          morphs = s['meshes'][mesh_names.index(m[:mesh])]['morphs']
          if m[:morph].is_a?(String)
            n = morphs.count(m[:morph])
            if n.zero?
              c.err(m[:path], %("#{m[:morph]}" is not a morph target of "#{m[:mesh]}"))
            elsif n > 1
              c.err(m[:path], %("#{m[:morph]}" names #{n} morph targets of "#{m[:mesh]}"; rename them so it is unique))
            end
          elsif m[:morph] >= morphs.size
            c.err(m[:path], %(mesh "#{m[:mesh]}" has #{morphs.size} morph target#{morphs.size == 1 ? '' : 's'}; index #{Beeper::Gltf.num(m[:morph])} is out of range))
          end
        end
      end

      # Draw calls the outlines add: each outlined material's primitives draw twice.
      def outline_draw_calls(materials, summary, stats)
        return 0 unless materials.is_a?(Array)

        named = {}
        star = false
        materials.each do |m|
          next unless m.is_a?(Hash) && m['material'].is_a?(String) && m['toon'].is_a?(Hash)

          outlined = m['toon'].key?('outline')
          if m['material'] == '*'
            star = outlined
          else
            named[m['material']] = outlined
          end
        end
        extra = 0
        summary['materials'].each_with_index do |name, i|
          outlined = name != '' && named.key?(name) ? named[name] : star
          extra += stats['materialDrawCalls'][i] || 0 if outlined
        end
        extra
      end

      # Outlined primitives draw twice (spec §4.7): the total must stay within maxDrawCalls.
      def check_draw_calls(c, materials, summary, stats)
        extra = outline_draw_calls(materials, summary, stats)
        total = stats['drawCalls'] + extra
        return unless extra.positive? && total > c.limits['maxDrawCalls']

        c.err('materials', "outlines raise the draw calls to #{total}; the limit is #{c.limits['maxDrawCalls']}")
      end

      # The error list and the helpers that add to it (the TypeScript core's Ctx).
      class Checker
        attr_reader :errors, :refs, :morphs, :limits

        def initialize(limits)
          @limits = limits
          @errors = []
          @refs = []
          @morphs = []
        end

        def err(path, message)
          @errors << "#{path}: #{message}"
        end

        def sub(path, key)
          path.empty? ? key.to_s : "#{path}.#{key}"
        end

        # An object with only allowed keys and all required keys present.
        def object(value, path, allowed, required)
          unless value.is_a?(Hash)
            err(path, 'must be an object')
            return false
          end
          value.each_key { |key| err(sub(path, key), 'unknown key') unless allowed.include?(key) }
          required.each { |key| err(sub(path, key), 'required') unless value.key?(key) }
          true
        end

        def number?(value)
          Manifests.number?(value)
        end

        def integer?(value)
          number?(value) && value == value.floor
        end

        def num(value, path, min, max, integer: false)
          unless integer ? integer?(value) : number?(value)
            err(path, integer ? 'must be an integer' : 'must be a number')
            return false
          end
          if value < min || value > max
            err(path, "must be between #{Beeper::Gltf.num(min)} and #{Beeper::Gltf.num(max)}")
            return false
          end
          true
        end

        def one_of(value, path, values)
          return true if value.is_a?(String) && values.include?(value)

          err(path, "must be one of #{values.map { |v| %("#{v}") }.join(', ')}")
          false
        end

        # JSON Schema string lengths count code points (Ruby's String#length on UTF-8).
        def name(value, path)
          return true if value.is_a?(String) && value.length.between?(1, 128)

          err(path, 'must be a name of 1 to 128 characters')
          false
        end

        def pattern(value, path, regexp, max_length, what)
          return true if value.is_a?(String) && value.length <= max_length && value.match?(regexp)

          err(path, "must be #{what}")
          false
        end

        def color(value, path)
          pattern(value, path, HEX, 7, 'a colour like "#RRGGBB"')
        end

        def bool(value, path)
          return true if [true, false].include?(value)

          err(path, 'must be true or false')
          false
        end

        # Two numbers; the block checks each (default: any finite number).
        def pair(value, path)
          unless value.is_a?(Array) && value.size == 2
            err(path, 'must be an array of 2 numbers')
            return false
          end
          ok = true
          2.times do |i|
            p = "#{path}[#{i}]"
            if block_given?
              ok = yield(value[i], p) && ok
            elsif !number?(value[i])
              err(p, 'must be a number')
              ok = false
            end
          end
          ok
        end

        def array(value, path, min, max)
          unless value.is_a?(Array)
            err(path, 'must be an array')
            return false
          end
          unless value.size.between?(min, max)
            err(path, "must have #{min} to #{max} items")
            return false
          end
          true
        end

        def ref(kind, name, path)
          @refs << { kind: kind, name: name, path: path }
        end
      end
    end
  end
end
