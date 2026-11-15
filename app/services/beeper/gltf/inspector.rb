require 'set'
require 'strscan'

module Beeper
  module Gltf
    # GLB inspection (spec §6.3): structure, self-containment, limits, and the scene summary the
    # manifest validator resolves names against. A port of inspectGlb in the shared TypeScript core
    # (specs/gltf-visualizer/ts/glb.ts): same checks, same "<path>: <message>" errors with paths
    # under "scene", same summary and stats shapes (string keys, camelCase as in TS). Keep the two
    # in step.
    #
    #   result = Beeper::Gltf::Inspector.call(bytes)
    #   result.errors   # ["scene.images[0]: 4096×16 exceeds 2048×2048", ...]
    #   result.summary  # { "nodes" => [...], "meshes" => [{ "name", "morphs" }], "materials",
    #                   #   "animations" => [{ "name", "duration" }], "lights", "cameras" } | nil
    #   result.stats    # { "bytes", "nodes", ..., "triangles", "vertices", "drawCalls",
    #                   #   "materialDrawCalls", "images" => [{ "index", "mime", "width", "height",
    #                   #   "bytes" }], "texturePixels", "clips" => [{ "name", "duration",
    #                   #   "keyframes" }], "keyframes" } | nil
    #
    # summary and stats are nil when the file is not a readable GLB (header, chunks or JSON).
    #
    # Work is bounded against crafted files, with the TypeScript core's numbers and messages: at
    # most MAX_ERRORS errors and one "scene: …and N more problems"; an array longer than
    # SKIP_FACTOR × its limit (MAX_UNBOUNDED_ARRAY without one) gets one error and counts as empty;
    # only the first maxImages images are inspected, each bufferView's header read once, in place;
    # JPEG scans stop after MAX_JPEG_MARKERS markers. result.capped says a cap was hit (such results
    # are not memoised).
    class Inspector
      Result = Struct.new(:errors, :summary, :stats, :capped) do
        def ok?
          errors.empty?
        end
      end

      MAGIC_GLTF = 0x46546c67 # "glTF"
      CHUNK_JSON = 0x4e4f534a # "JSON"
      CHUNK_BIN = 0x004e4942 # "BIN\0"

      COMPONENT_SIZES = { 5120 => 1, 5121 => 1, 5122 => 2, 5123 => 2, 5125 => 4, 5126 => 4 }.freeze
      TYPE_COMPONENTS = { 'SCALAR' => 1, 'VEC2' => 2, 'VEC3' => 3, 'VEC4' => 4, 'MAT2' => 4, 'MAT3' => 9, 'MAT4' => 16 }.freeze
      INDEX_SIZES = { 5121 => 1, 5123 => 2, 5125 => 4 }.freeze

      # Work bounds (the same numbers and messages as glb.ts).
      MAX_ERRORS = 100
      SKIP_FACTOR = 4
      MAX_UNBOUNDED_ARRAY = 65_536
      # Nesting deeper than 100 is refused in both TS and Ruby, by the same pre-parse bracket scan.
      MAX_JSON_DEPTH = 100
      MAX_JPEG_MARKERS = ImageHeader::MAX_JPEG_MARKERS

      def self.call(bytes, limits = Gltf::LIMITS)
        new(bytes, limits).call
      end

      # True when JSON text nests arrays/objects deeper than max (jsonTooDeep in glb.ts): outside
      # strings '[' and '{' add one and ']' and '}' subtract one; '"' opens a string, inside which
      # a backslash skips the next character and '"' closes it. The outermost value is depth 1.
      # Runs before parsing, so it decides for invalid JSON too.
      def self.json_too_deep?(text, max = MAX_JSON_DEPTH)
        scanner = StringScanner.new(text)
        depth = 0
        until scanner.eos?
          scanner.skip(/[^"\[\]{}]+/)
          case scanner.getch
          when '"'
            scanner.skip(/(?>[^"\\]+|\\.)*/m)
            scanner.getch # the closing quote, or a backslash ending the text
          when '[', '{'
            depth += 1
            return true if depth > max
          when ']', '}'
            depth -= 1
          end
        end
        false
      end

      def initialize(bytes, limits = Gltf::LIMITS)
        @bytes = bytes.encoding == Encoding::BINARY ? bytes : bytes.dup.force_encoding(Encoding::BINARY)
        @limits = limits
        @errors = []
        @dropped = 0
        @capped = false
      end

      def call
        header_error = read_container
        return fatal(header_error) if header_error

        # Arrays inspected only for their length.
        %w[samplers textures scenes].each do |key|
          capped("scene.#{key}", key, @json[key], nil) if @json[key].is_a?(Array)
        end
        check_asset_and_extensions
        check_buffers
        check_buffer_views
        check_accessors
        image_stats, texture_pixels = check_images
        counts = check_counts
        meshes = check_meshes
        instances, light_nodes, camera_nodes = check_nodes(meshes[:count])
        totals = draw_totals(meshes, instances)
        clips, keyframes = check_animations

        summary = {
          'nodes' => @nodes.map { |node| name_of(node) },
          'meshes' => meshes[:summaries],
          'materials' => @materials.map { |material| name_of(material) },
          'animations' => clips.map { |c| { 'name' => c['name'], 'duration' => c['duration'] } },
          'lights' => light_nodes,
          'cameras' => camera_nodes
        }
        stats = {
          'bytes' => @bytes.bytesize,
          'nodes' => counts[:nodes],
          'meshes' => counts[:meshes],
          'materials' => counts[:materials],
          'skins' => counts[:skins],
          'lights' => counts[:lights],
          'cameras' => counts[:cameras],
          'morphTargets' => meshes[:morph_targets],
          'triangles' => totals[:triangles],
          'vertices' => totals[:vertices],
          'drawCalls' => totals[:draw_calls],
          'materialDrawCalls' => totals[:material_draw_calls],
          'images' => image_stats,
          'texturePixels' => texture_pixels,
          'clips' => clips,
          'keyframes' => keyframes
        }
        if @dropped.positive?
          @capped = true
          @errors << "scene: …and #{@dropped} more problem#{@dropped == 1 ? '' : 's'}"
        end
        Result.new(@errors, summary, stats, @capped)
      end

      private

      def lim(key)
        @limits.fetch(key)
      end

      # Keeps the first MAX_ERRORS errors; the rest are counted for one closing line.
      def err(path, message)
        if @errors.size < MAX_ERRORS
          @errors << "#{path}: #{message}"
        else
          @dropped += 1
        end
      end

      def fatal(message)
        @errors << "scene: #{message}"
        Result.new(@errors, nil, nil, false)
      end

      # Over SKIP_FACTOR × limit (or MAX_UNBOUNDED_ARRAY without one): one "<n> <noun>; the limit is
      # <limit>" error and the array counts as empty from then on, so nothing iterates it.
      def capped(path, noun, array, limit)
        return array if array.size <= (limit.nil? ? MAX_UNBOUNDED_ARRAY : SKIP_FACTOR * limit)

        @capped = true
        err(path, "#{array.size} #{noun}; the limit is #{limit.nil? ? MAX_UNBOUNDED_ARRAY : limit}")
        []
      end

      def u32(offset)
        @bytes.byteslice(offset, 4).unpack1('V')
      end

      def obj?(value)
        value.is_a?(Hash)
      end

      # A JSON number with no fractional part (JavaScript's Number.isInteger).
      def int?(value)
        (value.is_a?(Integer) || (value.is_a?(Float) && value.finite? && value == value.floor))
      end

      def name_of(value)
        obj?(value) && value['name'].is_a?(String) ? value['name'] : ''
      end

      def num(value)
        Gltf.num(value)
      end

      # Header, the JSON chunk and the optional BIN chunk. Returns a fatal message or nil.
      def read_container
        n = @bytes.bytesize
        return "the file is #{Gltf.mb(n)}; the limit is #{Gltf.mb(lim('glbMaxBytes'))}" if n > lim('glbMaxBytes')
        return 'not a GLB file (too short); export glTF Binary (.glb)' if n < 20
        return 'not a GLB file (no glTF magic); export glTF Binary (.glb)' if u32(0) != MAGIC_GLTF
        return "GLB version #{u32(4)}; only version 2 is supported" if u32(4) != 2
        return "the header says #{u32(8)} bytes but the file has #{n}" if u32(8) != n

        json_length = u32(12)
        return 'the first chunk is not JSON' if u32(16) != CHUNK_JSON
        return 'the JSON chunk length is not a multiple of 4' unless (json_length % 4).zero?
        return 'the JSON chunk runs past the end of the file' if 20 + json_length > n
        if json_length > lim('jsonChunkMaxBytes')
          return "the JSON chunk is #{Gltf.mb(json_length)}; the limit is #{Gltf.mb(lim('jsonChunkMaxBytes'))}"
        end

        text = @bytes.byteslice(20, json_length).force_encoding(Encoding::UTF_8)
        return 'the JSON chunk is not valid UTF-8' unless text.valid_encoding?
        return 'JSON nested too deeply' if self.class.json_too_deep?(text)

        begin
          @json = JSON.parse(text)
        rescue JSON::ParserError
          return 'the JSON chunk is not valid JSON'
        end
        return 'the JSON chunk is not an object' unless obj?(@json)

        @bin_start = 0
        @bin_length = 0
        offset = 20 + json_length
        if offset < n
          return 'a truncated chunk follows the JSON chunk' if offset + 8 > n

          length = u32(offset)
          return 'only one BIN chunk may follow the JSON chunk' if u32(offset + 4) != CHUNK_BIN
          return 'the BIN chunk runs past the end of the file' if offset + 8 + length > n

          @bin_start = offset + 8
          @bin_length = length
          offset += 8 + length
          return 'unexpected data after the BIN chunk' if offset != n
        end
        nil
      end

      # json[key] as an array; absent → []; anything else is an error (once) and []; longer than
      # the cap for limit (see #capped) → one error and [].
      def array_of(key, limit = nil)
        return [] unless @json.key?(key)

        value = @json[key]
        return capped("scene.#{key}", key, value, limit) if value.is_a?(Array)

        err("scene.#{key}", 'must be an array')
        []
      end

      def check_asset_and_extensions
        asset = @json['asset']
        err('scene.asset.version', 'must be "2.0"') unless obj?(asset) && asset['version'] == '2.0'

        @used = array_of('extensionsUsed')
        allowed = lim('allowedExtensions')
        rejected = lim('rejectedExtensions')
        @used.each_with_index do |ext, i|
          if !ext.is_a?(String)
            err("scene.extensionsUsed[#{i}]", 'must be a string')
          elsif !allowed.include?(ext)
            why = rejected.key?(ext) ? rejected[ext] : "not supported (allowed: #{allowed.join(', ')})"
            err('scene.extensionsUsed', "#{ext}: #{why}")
          end
        end
        used = @used.select { |ext| ext.is_a?(String) }.to_set # linear, not include? per entry
        array_of('extensionsRequired').each do |ext|
          next if ext.is_a?(String) && used.include?(ext)

          err('scene.extensionsRequired', "#{Gltf.js_string(ext)} is not listed in extensionsUsed")
        end
      end

      # One buffer, no uri, inside the BIN chunk.
      def check_buffers
        @buffers = array_of('buffers')
        err('scene.buffers', "#{@buffers.size} buffers; a GLB has one, its BIN chunk") if @buffers.size > 1
        @buffer_length = 0
        @buffers.each_with_index do |buffer, i|
          unless obj?(buffer)
            err("scene.buffers[#{i}]", 'must be an object')
            next
          end
          err("scene.buffers[#{i}].uri", 'external and data-URI buffers are not allowed; export GLB') if buffer.key?('uri')
          next unless i.zero?

          length = buffer['byteLength']
          if !int?(length) || length.negative?
            err('scene.buffers[0].byteLength', 'must be a non-negative integer')
          elsif length > @bin_length
            err('scene.buffers[0].byteLength', "#{num(length)} exceeds the BIN chunk (#{@bin_length} bytes)")
          else
            @buffer_length = length.to_i
          end
        end
      end

      # bufferViews inside the buffer.
      def check_buffer_views
        @views = array_of('bufferViews')
        @view_ok = []
        @view_start = [] # offset in the file
        @view_length = []
        @view_stride = []
        @views.each_with_index do |view, i|
          path = "scene.bufferViews[#{i}]"
          @view_ok << false
          @view_start << 0
          @view_length << 0
          @view_stride << 0
          unless obj?(view)
            err(path, 'must be an object')
            next
          end
          offset = view.key?('byteOffset') ? view['byteOffset'] : 0
          length = view['byteLength']
          stride = view['byteStride']
          if view['buffer'] != 0 || @buffers.empty?
            err("#{path}.buffer", 'no such buffer')
          elsif !int?(offset) || offset.negative?
            err("#{path}.byteOffset", 'must be a non-negative integer')
          elsif !int?(length) || length < 1
            err("#{path}.byteLength", 'must be a positive integer')
          elsif view.key?('byteStride') && !(int?(stride) && stride >= 4 && stride <= 252 && (stride % 4).zero?)
            err("#{path}.byteStride", 'must be a multiple of 4 between 4 and 252')
          elsif offset + length > @buffer_length
            err(path, "bytes #{num(offset)}..#{num(offset + length)} lie outside the buffer (#{@buffer_length} bytes)")
          else
            @view_ok[i] = true
            @view_start[i] = @bin_start + offset.to_i
            @view_length[i] = length.to_i
            @view_stride[i] = int?(stride) ? stride.to_i : 0
          end
        end
      end

      def view_index?(view)
        int?(view) && view >= 0 && view < @views.size
      end

      def view_range(path, view, start, finish)
        if !view_index?(view)
          err("#{path}.bufferView", 'no such bufferView')
        elsif @view_ok[view.to_i] && finish > @view_length[view.to_i]
          err(path, "needs bytes #{num(start)}..#{num(finish)} of bufferView #{num(view)}, which has #{@view_length[view.to_i]}")
        end
      end

      def component_size(type, table = COMPONENT_SIZES)
        int?(type) ? table.fetch(type.to_i, 0) : 0
      end

      # Accessors inside their bufferViews (sparse too). Element size = component size × component
      # count, with no matrix column padding (as in the TypeScript core).
      def check_accessors
        @accessors = array_of('accessors')
        @acc_count = []
        @accessors.each_with_index do |accessor, i|
          path = "scene.accessors[#{i}]"
          @acc_count << -1
          unless obj?(accessor)
            err(path, 'must be an object')
            next
          end
          size = accessor['componentType'].is_a?(Numeric) ? component_size(accessor['componentType']) : 0
          components = accessor['type'].is_a?(String) ? TYPE_COMPONENTS.fetch(accessor['type'], 0) : 0
          count = accessor['count']
          err("#{path}.componentType", 'must be one of 5120, 5121, 5122, 5123, 5125, 5126') if size.zero?
          err("#{path}.type", 'must be one of SCALAR, VEC2, VEC3, VEC4, MAT2, MAT3, MAT4') if components.zero?
          valid_count = int?(count) && count >= 1
          err("#{path}.count", 'must be a positive integer') unless valid_count
          next if size.zero? || components.zero? || !valid_count

          count = count.to_i
          element = size * components
          if accessor.key?('bufferView')
            offset = accessor.key?('byteOffset') ? accessor['byteOffset'] : 0
            if !int?(offset) || offset.negative?
              err("#{path}.byteOffset", 'must be a non-negative integer')
              next
            end
            view = accessor['bufferView']
            stride = view_index?(view) && @view_stride[view.to_i].positive? ? @view_stride[view.to_i] : element
            view_range(path, view, offset, offset + (stride * (count - 1)) + element)
          end
          check_sparse(accessor['sparse'], "#{path}.sparse", count, element) if accessor.key?('sparse')
          @acc_count[i] = count
        end
      end

      def check_sparse(sparse, path, count, element)
        sparse_count = obj?(sparse) ? sparse['count'] : nil
        unless int?(sparse_count) && sparse_count >= 1 && sparse_count <= count
          err("#{path}.count", "must be an integer from 1 to the accessor count (#{count})")
          return
        end
        indices = sparse['indices']
        values = sparse['values']
        index_size = obj?(indices) && indices['componentType'].is_a?(Numeric) ? component_size(indices['componentType'], INDEX_SIZES) : 0
        if !obj?(indices) || index_size.zero?
          err("#{path}.indices", 'needs a bufferView and an unsigned componentType')
        else
          offset = indices.key?('byteOffset') ? indices['byteOffset'] : 0
          if !int?(offset) || offset.negative?
            err("#{path}.indices.byteOffset", 'must be a non-negative integer')
          else
            view_range("#{path}.indices", indices['bufferView'], offset, offset + (sparse_count * index_size))
          end
        end
        if !obj?(values)
          err("#{path}.values", 'needs a bufferView')
        else
          offset = values.key?('byteOffset') ? values['byteOffset'] : 0
          if !int?(offset) || offset.negative?
            err("#{path}.values.byteOffset", 'must be a non-negative integer')
          else
            view_range("#{path}.values", values['bufferView'], offset, offset + (sparse_count * element))
          end
        end
      end

      def accessor_count(ref)
        int?(ref) && ref >= 0 && ref < @acc_count.size ? @acc_count[ref.to_i] : -1
      end

      # Embedded PNG/JPEG, header dimensions within the limits. Returns [image stats, pixels]. Past
      # maxImages only the count error is reported; headers are read once per bufferView, in place.
      def check_images
        images = array_of('images', lim('maxImages'))
        err('scene.images', "#{images.size} images; the limit is #{lim('maxImages')}") if images.size > lim('maxImages')
        stats = []
        headers = {} # bufferView index → { mime: sniffed, size: }
        pixels = 0
        mimes = lim('imageMimeTypes')
        max = lim('maxTextureSize')
        images.first(lim('maxImages')).each_with_index do |image, i|
          path = "scene.images[#{i}]"
          unless obj?(image)
            err(path, 'must be an object')
            next
          end
          if image.key?('uri')
            err("#{path}.uri", 'images must be embedded in the GLB (bufferView), not referenced by uri')
            next
          end
          view = image['bufferView']
          unless view_index?(view)
            err(path, 'needs a bufferView')
            next
          end
          mime = image['mimeType']
          unless mime.is_a?(String) && mimes.include?(mime)
            err("#{path}.mimeType", "#{Gltf.js_string(mime, present: image.key?('mimeType'))}; textures must be #{mimes.join(' or ')}")
            next
          end
          view = view.to_i
          next unless @view_ok[view] # its bufferView already has an error

          head = headers[view] ||= begin
            start = @view_start[view]
            length = @view_length[view]
            sniffed = ImageHeader.sniff(@bytes, start, length)
            { mime: sniffed, size: sniffed && ImageHeader.size(@bytes, sniffed, start, length),
              complete: !sniffed.nil? && ImageHeader.trailer?(@bytes, sniffed, start, length) }
          end
          kind = mime == 'image/png' ? 'PNG' : 'JPEG'
          if head[:mime] != mime
            err(path, "the bytes are not a #{kind} (mimeType says #{mime})")
            next
          end
          size = head[:size]
          if size.nil?
            err(path, "can't read the #{kind} header")
            next
          end
          unless head[:complete]
            err(path, "the #{kind} is cut short (no #{kind == 'PNG' ? 'IEND' : 'EOI'})")
            next
          end
          if size[:width] > max || size[:height] > max
            err(path, "#{size[:width]}×#{size[:height]} exceeds #{max}×#{max}")
          end
          pixels += size[:width] * size[:height]
          stats << { 'index' => i, 'mime' => mime, 'width' => size[:width], 'height' => size[:height],
                     'bytes' => @view_length[view] }
        end
        if pixels > lim('maxTexturePixels')
          err('scene.images', "#{pixels} pixels in total; the limit is #{lim('maxTexturePixels')}")
        end
        [stats, pixels]
      end

      # Scene graph counts against the limits.
      def check_counts
        @nodes = array_of('nodes', lim('maxNodes'))
        @meshes = array_of('meshes', lim('maxMeshes'))
        @materials = array_of('materials', lim('maxMaterials'))
        @skins = array_of('skins', lim('maxSkins'))
        @cameras = array_of('cameras', lim('maxCameras'))
        @animations = array_of('animations', lim('maxAnimations'))
        extensions = @json['extensions']
        lights_ext = obj?(extensions) && obj?(extensions['KHR_lights_punctual']) ? extensions['KHR_lights_punctual'] : nil
        @lights = if lights_ext && lights_ext['lights'].is_a?(Array)
                    capped('scene.extensions.KHR_lights_punctual.lights', 'lights', lights_ext['lights'], lim('maxLights'))
                  else
                    []
                  end
        limit_error('scene.nodes', @nodes.size, 'maxNodes', 'nodes')
        limit_error('scene.meshes', @meshes.size, 'maxMeshes', 'meshes')
        limit_error('scene.materials', @materials.size, 'maxMaterials', 'materials')
        limit_error('scene.skins', @skins.size, 'maxSkins', 'skins')
        @skins.each_with_index do |skin, i|
          joints = obj?(skin) && skin['joints'].is_a?(Array) ? skin['joints'].size : 0
          limit_error("scene.skins[#{i}].joints", joints, 'maxJoints', 'joints')
        end
        limit_error('scene.cameras', @cameras.size, 'maxCameras', 'cameras')
        limit_error('scene.extensions.KHR_lights_punctual.lights', @lights.size, 'maxLights', 'lights')
        { nodes: @nodes.size, meshes: @meshes.size, materials: @materials.size, skins: @skins.size,
          lights: @lights.size, cameras: @cameras.size }
      end

      def limit_error(path, count, key, noun)
        err(path, "#{count} #{noun}; the limit is #{lim(key)}") if count > lim(key)
      end

      # Per mesh: triangles, vertices, the material of each primitive, morph targets.
      def check_meshes
        out = { count: @meshes.size, triangles: [], vertices: [], materials: [], summaries: [], morph_targets: 0 }
        @meshes.each_with_index do |mesh, m|
          path = "scene.meshes[#{m}]"
          triangles = 0
          vertices = 0
          targets = 0
          materials = []
          listed = obj?(mesh) && mesh['primitives'].is_a?(Array)
          primitives = listed ? capped("#{path}.primitives", 'primitives', mesh['primitives'], lim('maxDrawCalls')) : []
          err("#{path}.primitives", 'must be an array') unless listed
          primitives.each_with_index do |prim, p|
            pp = "#{path}.primitives[#{p}]"
            unless obj?(prim) && obj?(prim['attributes'])
              err("#{pp}.attributes", 'must be an object')
              materials << -1
              next
            end
            positions = 0
            if prim['attributes'].key?('POSITION')
              positions = accessor_count(prim['attributes']['POSITION'])
              if positions.negative?
                err("#{pp}.attributes.POSITION", 'no such accessor')
                positions = 0
              end
            end
            drawn = positions
            if prim.key?('indices')
              drawn = accessor_count(prim['indices'])
              if drawn.negative?
                err("#{pp}.indices", 'no such accessor')
                drawn = 0
              end
            end
            mode = prim.key?('mode') ? prim['mode'] : 4
            if mode == 4
              triangles += drawn / 3
            elsif [5, 6].include?(mode)
              triangles += [drawn - 2, 0].max
            end
            vertices += positions
            targets = [targets, prim['targets'].size].max if prim['targets'].is_a?(Array)
            material = -1
            if prim.key?('material')
              if int?(prim['material']) && prim['material'] >= 0 && prim['material'] < @materials.size
                material = prim['material'].to_i
              else
                err("#{pp}.material", 'no such material')
              end
            end
            materials << material
          end
          err(path, "#{targets} morph targets; the limit is #{lim('maxMorphTargets')}") if targets > lim('maxMorphTargets')
          out[:morph_targets] += targets
          extras = obj?(mesh) && obj?(mesh['extras']) ? mesh['extras'] : nil
          names = extras && extras['targetNames'].is_a?(Array) ? extras['targetNames'] : []
          # Names are listed only up to SKIP_FACTOR × the limit; past the limit the error above stands.
          morphs = targets <= SKIP_FACTOR * lim('maxMorphTargets') ? Array.new(targets) { |t| names[t].is_a?(String) ? names[t] : '' } : []
          out[:summaries] << { 'name' => name_of(mesh), 'morphs' => morphs }
          out[:triangles] << triangles
          out[:vertices] << vertices
          out[:materials] << materials
        end
        out
      end

      # Instancing, lights, cameras, skins. Returns [instances per mesh, light nodes, camera nodes].
      def check_nodes(mesh_count)
        instances = Array.new(mesh_count, 0)
        light_nodes = []
        camera_nodes = []
        @nodes.each_with_index do |node, i|
          path = "scene.nodes[#{i}]"
          unless obj?(node)
            err(path, 'must be an object')
            next
          end
          if node.key?('mesh')
            if int?(node['mesh']) && node['mesh'] >= 0 && node['mesh'] < mesh_count
              instances[node['mesh'].to_i] += 1
            else
              err("#{path}.mesh", 'no such mesh')
            end
          end
          if node.key?('camera')
            if int?(node['camera']) && node['camera'] >= 0 && node['camera'] < @cameras.size
              camera_nodes << name_of(node)
            else
              err("#{path}.camera", 'no such camera')
            end
          end
          if node.key?('skin') && !(int?(node['skin']) && node['skin'] >= 0 && node['skin'] < @skins.size)
            err("#{path}.skin", 'no such skin')
          end
          ext = obj?(node['extensions']) && obj?(node['extensions']['KHR_lights_punctual']) ? node['extensions']['KHR_lights_punctual'] : nil
          next unless ext

          if int?(ext['light']) && ext['light'] >= 0 && ext['light'] < @lights.size
            light_nodes << name_of(node)
          else
            err("#{path}.extensions.KHR_lights_punctual.light", 'no such light')
          end
        end
        [instances, light_nodes, camera_nodes]
      end

      def draw_totals(meshes, instances)
        triangles = 0
        vertices = 0
        draw_calls = 0
        material_draw_calls = Array.new(@materials.size, 0)
        meshes[:count].times do |m|
          k = instances[m]
          triangles += meshes[:triangles][m] * k
          vertices += meshes[:vertices][m] * k
          mats = meshes[:materials][m]
          draw_calls += mats.size * k
          mats.each { |mat| material_draw_calls[mat] += k if mat >= 0 }
        end
        err('scene', "#{triangles} triangles; the limit is #{lim('maxTriangles')}") if triangles > lim('maxTriangles')
        err('scene', "#{vertices} vertices; the limit is #{lim('maxVertices')}") if vertices > lim('maxVertices')
        err('scene', "#{draw_calls} draw calls; the limit is #{lim('maxDrawCalls')}") if draw_calls > lim('maxDrawCalls')
        { triangles: triangles, vertices: vertices, draw_calls: draw_calls, material_draw_calls: material_draw_calls }
      end

      # Input max (required by glTF) gives the duration; keyframes = Σ input counts.
      def check_animations
        if @animations.size > lim('maxAnimations')
          err('scene.animations', "#{@animations.size} animations; the limit is #{lim('maxAnimations')}")
        end
        clips = []
        keyframes = 0
        @animations.each_with_index do |animation, i|
          path = "scene.animations[#{i}]"
          samplers = obj?(animation) && animation['samplers'].is_a?(Array) ? capped("#{path}.samplers", 'samplers', animation['samplers'], nil) : []
          duration = 0
          keys = 0
          samplers.each_with_index do |sampler, j|
            sp = "#{path}.samplers[#{j}].input"
            input = obj?(sampler) ? sampler['input'] : nil
            count = accessor_count(input)
            if count.negative?
              err(sp, 'no such accessor')
              next
            end
            keys += count
            max = @accessors[input.to_i]['max']
            if max.is_a?(Array) && max[0].is_a?(Numeric) && max[0].to_f.finite?
              duration = [duration, max[0]].max
            else
              err(sp, "accessor #{num(input)} has no max (glTF requires min/max on animation inputs)")
            end
          end
          if duration > lim('maxAnimationSeconds')
            err(path, "#{num(duration)} s long; the limit is #{num(lim('maxAnimationSeconds'))} s")
          end
          clips << { 'name' => name_of(animation), 'duration' => duration, 'keyframes' => keys }
          keyframes += keys
        end
        if keyframes > lim('maxKeyframes')
          err('scene.animations', "#{keyframes} keyframes; the limit is #{lim('maxKeyframes')}")
        end
        [clips, keyframes]
      end
    end
  end
end
