module Beeper
  module Gltf
    # A glTF visualizer manifest in words, for reviewers (spec §7): one line per binding, per
    # noteClips rule, per idle clip, per material override, and the view, with defaults filled in
    # as the runtime applies them (limits.outputDefaults, default axes, fades).
    #
    #   Beeper::Gltf::BindingsSummary.call(manifest)
    #   # => [["Bindings", ["kick → Cone.scale xyz 1 → 1.25, easeOut, attack 0 ms, release 140 ms (kick-thump)", ...]],
    #   #     ["Note → clip", [...]], ["Idle", [...]], ["Materials (toon)", [...]], ["View", [...]]]
    #
    # Sections with nothing in them are left out. Never raises: a part it can't read (a draft can
    # hold an invalid manifest) becomes "(unreadable)".
    module BindingsSummary
      DEFAULT_FADE_MS = 250
      DEFAULT_THRESHOLD = 0.5

      module_function

      def call(manifest)
        manifest = manifest.is_a?(Hash) ? manifest.deep_stringify_keys : {}
        audio = manifest['audio'].is_a?(Hash) ? manifest['audio'] : {}
        [
          ['Bindings', list(audio['bindings']) { |b| binding_line(b) }],
          ['Note → clip', note_clip_lines(audio['noteClips'])],
          ['Idle', list(audio.dig('idle', 'clips')) { |c| idle_line(c) }],
          ['Materials (toon)', list(manifest['materials']) { |m| material_line(m) }],
          ['View', view_lines(manifest['view'])]
        ].reject { |_, lines| lines.empty? }
      end

      def list(items, &block)
        return [] unless items.is_a?(Array)

        items.map { |item| safely { block.call(item) } }
      end

      def safely
        yield
      rescue StandardError
        '(unreadable)'
      end

      def n(value)
        Gltf.num(value)
      end

      def binding_line(b)
        target = b['target'].is_a?(Hash) ? b['target'] : {}
        parts = ["#{source_text(b)} → #{target_text(target)}"]
        range = output_range(b, target)
        parts[0] += " #{n(range[0])} → #{n(range[1])}" if range
        details = []
        details << "in #{n(b['inputRange'][0])}..#{n(b['inputRange'][1])}" if b['inputRange'].is_a?(Array)
        curve = b['curve'] || 'linear'
        details << (curve == 'step' ? "step × #{n(b['steps'] || 4)}" : curve)
        details << 'inverted' if b['invert'] == true
        smoothing = b['smoothing']
        if smoothing.is_a?(Hash)
          details << "attack #{n(smoothing['attackMs'] || 0)} ms"
          details << "release #{n(smoothing['releaseMs'] || 0)} ms"
        end
        line = ([parts[0]] + details).join(', ')
        b['id'].is_a?(String) ? "#{line} (#{b['id']})" : line
      end

      def source_text(b)
        return b['source'].to_s unless b['sources'].is_a?(Array)

        terms = b['sources'].map do |s|
          weight = s.is_a?(Hash) && s.key?('weight') ? s['weight'] : 1
          name = s.is_a?(Hash) ? s['source'] : s
          weight == 1 ? name.to_s : "#{n(weight)}×#{name}"
        end
        "#{b['combine'] || 'sum'}(#{terms.join(', ')})"
      end

      def target_text(t)
        case t['kind']
        when 'clip'
          text = "clip #{t['clip']} #{t['mode']}"
          if %w[play trigger].include?(t['mode'])
            text += " at #{n(t['threshold'] || DEFAULT_THRESHOLD)}, fade #{n(t['fadeMs'] || DEFAULT_FADE_MS)} ms"
          end
          text
        when 'morph'
          t['morph'].is_a?(String) ? "#{t['mesh']} morph #{t['morph']}" : "#{t['mesh']} morph ##{n(t['morph'])}"
        when 'node'
          axis = t['axis'] || Beeper::Manifests::VisualizerGltf::DEFAULT_AXIS[t['property']]
          "#{t['node']}.#{t['property']} #{axis}".strip
        when 'material'
          colors = t['colors'].is_a?(Array) ? " #{t['colors'].join(' → ')}" : ''
          "#{t['material']}.#{t['property']}#{colors}"
        when 'light' then "#{t['light']}.intensity"
        when 'camera' then "camera.#{t['property']}"
        else '(unknown target)'
        end
      end

      # The output range the runtime uses: the binding's, else the target's default; nil for
      # play/trigger clip targets (they follow the threshold) and colour blends.
      def output_range(b, target)
        return nil if target['kind'] == 'clip' && %w[play trigger].include?(target['mode'])
        return nil if target['kind'] == 'material' && %w[color emissiveColor].include?(target['property'])
        return b['outputRange'] if b['outputRange'].is_a?(Array) && b['outputRange'].size == 2

        key = Beeper::Manifests::VisualizerGltf.output_key(target)
        key ? Gltf::LIMITS['outputDefaults'][key] : nil
      end

      def note_clip_lines(nc)
        return [] unless nc.is_a?(Hash)

        fade = nc['fadeMs'] || DEFAULT_FADE_MS
        head = safely do
          parts = ["start in #{nc['initial']}", "fade #{n(fade)} ms", "priority #{nc['priority'] || 'last'}",
                   "on stop #{nc['onStop'] || 'hold'}"]
          parts << "back to #{nc['initial']} after #{n(nc['returnAfterMs'])} ms of silence" if nc['returnAfterMs'].to_f.positive?
          parts.join(', ')
        end
        [head] + list(nc['rules']) { |rule| rule_line(rule, fade) }
      end

      def rule_line(rule, fade)
        parts = ["#{match_text(rule['match'])} → #{rule['clip']} #{rule['mode'] || 'loop'}"]
        parts << "sync #{rule['sync']}" if rule['sync'] && rule['sync'] != 'now'
        parts << "fade #{n(rule['fadeMs'])} ms" if rule.key?('fadeMs') && rule['fadeMs'] != fade
        parts << "×#{n(rule['timeScale'])}" if rule.key?('timeScale')
        parts << "tempo-synced to #{n(rule['clipBpm'])} BPM" if rule.key?('clipBpm')
        velocity = rule['velocity']
        if velocity.is_a?(Hash) && velocity['range'].is_a?(Array)
          parts << "velocity → #{velocity['to']} #{n(velocity['range'][0])}..#{n(velocity['range'][1])}"
        end
        parts.join(', ')
      end

      def match_text(match)
        return '(no match)' unless match.is_a?(Hash)

        case match['part']
        when 'drums'
          voices = match['voices'].is_a?(Array) ? match['voices'] : [match['voice']]
          "drums #{voices.join(', ')}"
        when 'sampler'
          lo, hi = match['slots'].is_a?(Array) ? match['slots'] : [match['slot'], match['slot']]
          lo == hi ? "sampler pad #{n(lo + 1)}" : "sampler pads #{n(lo + 1)}–#{n(hi + 1)}"
        else
          lo, hi = match['notes'].is_a?(Array) ? match['notes'] : [match['note'], match['note']]
          lo == hi ? "#{match['part']} note #{n(lo)}" : "#{match['part']} notes #{n(lo)}–#{n(hi)}"
        end
      end

      def idle_line(clip)
        scale = clip['timeScale'] || 1
        scale == 1 ? clip['clip'].to_s : "#{clip['clip']} ×#{n(scale)}"
      end

      def material_line(m)
        toon = m['toon'].is_a?(Hash) ? m['toon'] : {}
        name = m['material'] == '*' ? '* (every other material)' : m['material']
        text = "#{name}: #{n(toon['steps'])} steps"
        outline = toon['outline']
        text += ", outline #{n(outline['width'])} #{outline['color'] || '#000000'}" if outline.is_a?(Hash)
        text
      end

      def view_lines(view)
        view = {} unless view.is_a?(Hash)
        safely do
          camera = view['camera'].is_a?(Hash) ? view['camera'] : {}
          cam = if camera.key?('node')
                  "camera node #{camera['node']}"
                else
                  "camera fov #{n(camera['fov'] || 40)}°, distance ×#{n(camera['distance'] || 1)}, " \
                    "elevation #{n(camera['elevation'] || 10)}°, azimuth #{n(camera['azimuth'] || 0)}°"
                end
          orbit = camera['orbitSpeed'] || 0
          cam += ", orbit #{n(orbit)}°/s" unless orbit.zero?
          ["background #{view['background'] || '#000000'}, lighting #{view['lighting'] || 'studio'}, " \
           "exposure #{n(view['exposure'] || 1)}", cam]
        end.then { |lines| lines.is_a?(Array) ? lines : [lines] }
      end
    end
  end
end
