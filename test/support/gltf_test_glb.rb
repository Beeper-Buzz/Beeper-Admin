require 'zlib'

# A tiny GLB builder for the glTF visualizer tests: a Ruby port of the shared core's testGlb.ts
# (and the fixture scene of its __tests__/scenes.ts). Scenes are plain hashes, PNGs are real
# (stored deflate), JPEGs are header-only, and fault switches inject what the inspector must catch.
#
#   GltfTestGlb.build(nodes: [{ name: 'A', mesh: 0 }], meshes: [{ name: 'M', primitives: [GltfTestGlb.cube] }],
#                     materials: [{ name: 'Mat' }], faults: { bad_magic: true },
#                     edit_json: ->(json) { json['asset']['version'] = '1.0' })
#
# Faults: bad_magic, bad_version, wrong_length (header one word longer than the file),
# external_buffer_uri, image_uri (images[0] by uri), accessor_out_of_bounds: <index>,
# no_animation_max, extra_chunk (a third chunk after BIN).
module GltfTestGlb
  FLOAT = 5126
  UBYTE = 5121
  USHORT = 5123
  UINT = 5125
  TYPE_SIZE = { 'SCALAR' => 1, 'VEC2' => 2, 'VEC3' => 3, 'VEC4' => 4, 'MAT4' => 16 }.freeze
  ROT_Y_90 = [0, Math.sqrt(0.5), 0, Math.sqrt(0.5)].freeze

  module_function

  # --- images ------------------------------------------------------------------------------------

  def png_chunk(type, data)
    body = type.b + data.b
    [data.bytesize].pack('N') + body + [Zlib.crc32(body)].pack('N')
  end

  # A valid RGBA PNG (stored deflate blocks), or IHDR + IEND only when header_only.
  def png(width, height, header_only: false, rgba: [255, 0, 128, 255])
    out = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].pack('C*')
    out << png_chunk('IHDR', [width, height, 8, 6, 0, 0, 0].pack('NNC5'))
    unless header_only
      row = [0].pack('C') + (rgba.pack('C4') * width)
      raw = row * height
      out << png_chunk('IDAT', Zlib::Deflate.deflate(raw, Zlib::NO_COMPRESSION))
    end
    out << png_chunk('IEND', ''.b)
    out
  end

  # JPEG markers up to a valid SOF0 (header parsing only; not decodable).
  def jpeg_header(width, height)
    [0xff, 0xd8,
     0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
     0xff, 0xc0, 0x00, 0x11, 0x08, (height >> 8) & 0xff, height & 0xff, (width >> 8) & 0xff, width & 0xff,
     0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
     0xff, 0xd9].pack('C*')
  end

  # SOI, chain empty APP0 segments, then an SOF0 of width×height (jpegChain in glb.test.ts).
  def jpeg_chain(chain, width, height)
    out = [0xff, 0xd8]
    chain.times { out.push(0xff, 0xe0, 0x00, 0x02) }
    out.push(0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1)
    out.pack('C*')
  end

  # --- raw GLBs (work-bound tests) ----------------------------------------------------------------

  # A GLB from a JSON hash and BIN bytes, no builder conveniences (rawGlb in glb.test.ts).
  def raw_glb(json, bin)
    text = JSON.generate(json, max_nesting: false).b
    json_length = (text.bytesize + 3) & ~3
    bin_length = (bin.bytesize + 3) & ~3
    total = 12 + 8 + json_length + (bin.bytesize.positive? ? 8 + bin_length : 0)
    out = [0x46546c67, 2, total, json_length, 0x4e4f534a].pack('V5')
    out << text << (' ' * (json_length - text.bytesize)).b
    if bin.bytesize.positive?
      out << [bin_length, 0x004e4942].pack('V2') << bin.b << ("\0" * (bin_length - bin.bytesize)).b
    end
    out
  end

  # A GLB whose only bufferView holds data, referenced by count JPEG images (imagesOnOneView).
  def images_on_one_view(data, count)
    raw_glb({ 'asset' => { 'version' => '2.0' }, 'buffers' => [{ 'byteLength' => data.bytesize }],
              'bufferViews' => [{ 'buffer' => 0, 'byteLength' => data.bytesize }],
              'images' => Array.new(count) { { 'bufferView' => 0, 'mimeType' => 'image/jpeg' } } }, data)
  end

  # Arrays nested depth deep ([] is depth 1).
  def nest(depth)
    value = []
    (depth - 1).times { value = [value] }
    value
  end

  # --- geometry ----------------------------------------------------------------------------------

  # One triangle in the XY plane.
  def triangle(material = nil)
    { positions: [0, 0, 0, 1, 0, 0, 0, 1, 0], normals: [0, 0, 1, 0, 0, 1, 0, 0, 1], material: material }
  end

  # An indexed cube (8 vertices, 12 triangles) centred on the origin.
  def cube(size = 1, material = nil)
    h = size / 2.0
    positions = []
    normals = []
    8.times do |i|
      x = i & 1 != 0 ? h : -h
      y = i & 2 != 0 ? h : -h
      z = i & 4 != 0 ? h : -h
      positions.push(x, y, z)
      l = Math.sqrt(3) * h
      normals.push(x / l, y / l, z / l)
    end
    indices = [0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6, 0, 1, 4, 1, 5, 4, 2, 6, 3, 3, 6, 7, 0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5]
    { positions: positions, normals: normals, indices: indices, material: material }
  end

  # --- builder -----------------------------------------------------------------------------------

  def min_max(values, size)
    min = Array.new(size, Float::INFINITY)
    max = Array.new(size, -Float::INFINITY)
    values.each_with_index do |v, i|
      c = i % size
      min[c] = v if v < min[c]
      max[c] = v if v > max[c]
    end
    [min, max]
  end

  # Builds a GLB (binary String) from spec.
  def build(spec)
    Builder.new(spec).build
  end

  class Builder
    def initialize(spec)
      @spec = spec
      @faults = spec[:faults] || {}
      @parts = []
      @bin_length = 0
      @views = []
      @accessors = []
    end

    def add_view(data)
      pad = (4 - (@bin_length % 4)) % 4
      if pad.positive?
        @parts << ("\0" * pad).b
        @bin_length += pad
      end
      @views << { 'buffer' => 0, 'byteOffset' => @bin_length, 'byteLength' => data.bytesize }
      @parts << data.b
      @bin_length += data.bytesize
      @views.size - 1
    end

    def add_floats(values, type, with_bounds)
      size = TYPE_SIZE.fetch(type)
      accessor = { 'bufferView' => add_view(values.pack('e*')), 'componentType' => FLOAT,
                   'count' => values.size / size, 'type' => type }
      if with_bounds
        min, max = GltfTestGlb.min_max(values, size)
        accessor['min'] = min
        accessor['max'] = max
      end
      @accessors << accessor
      @accessors.size - 1
    end

    def add_indices(values)
      max = values.max
      data, type = if max < 256
                     [values.pack('C*'), UBYTE]
                   elsif max < 65_536
                     [values.pack('v*'), USHORT]
                   else
                     [values.pack('V*'), UINT]
                   end
      @accessors << { 'bufferView' => add_view(data), 'componentType' => type, 'count' => values.size, 'type' => 'SCALAR' }
      @accessors.size - 1
    end

    def build
      json = { 'asset' => { 'version' => '2.0', 'generator' => 'gltf-visualizer testGlb (Ruby)' } }
      used = Array(@spec[:extensions_used]).dup
      json['meshes'] = Array(@spec[:meshes]).map { |m| mesh(m) }
      json['materials'] = Array(@spec[:materials]).map { |m| material(m) }
      lights = Array(@spec[:lights])
      used << 'KHR_lights_punctual' if lights.any? && !used.include?('KHR_lights_punctual')
      json['nodes'] = @spec[:nodes].map { |n| node(n) }
      children = @spec[:nodes].flat_map { |n| Array(n[:children]) }
      json['scenes'] = [{ 'nodes' => (0...@spec[:nodes].size).reject { |i| children.include?(i) } }]
      json['scene'] = 0
      json['skins'] = @spec[:skins].map { |s| skin(s) } if @spec[:skins]
      json['cameras'] = @spec[:cameras].map { |c| camera(c) } if @spec[:cameras]
      json['extensions'] = { 'KHR_lights_punctual' => { 'lights' => lights.map { |l| light(l) } } } if lights.any?
      json['animations'] = Array(@spec[:animations]).map { |a| animation(a) }
      json['images'] = @spec[:images].each_with_index.map { |img, i| image(img, i) } if @spec[:images]
      @accessors[@faults[:accessor_out_of_bounds]]['count'] += 1000 if @faults.key?(:accessor_out_of_bounds)

      json['accessors'] = @accessors
      json['bufferViews'] = @views
      if @bin_length.positive?
        json['buffers'] = [{ 'byteLength' => @bin_length }]
        json['buffers'][0]['uri'] = 'scene.bin' if @faults[:external_buffer_uri]
      end
      json['extensionsUsed'] = used if used.any?
      json['extensionsRequired'] = @spec[:extensions_required] if @spec[:extensions_required]
      %w[meshes materials animations accessors bufferViews].each { |key| json.delete(key) if json[key] == [] }
      @spec[:edit_json]&.call(json)
      assemble(JSON.generate(json, max_nesting: false).b)
    end

    private

    def mesh(spec)
      out = { 'primitives' => spec[:primitives].map { |p| primitive(p) } }
      out['name'] = spec[:name] if spec.key?(:name)
      out['extras'] = { 'targetNames' => spec[:target_names] } if spec[:target_names]
      out['weights'] = spec[:weights] if spec[:weights]
      out
    end

    def primitive(spec)
      prim = { 'attributes' => { 'POSITION' => add_floats(spec[:positions], 'VEC3', true) } }
      prim['attributes']['NORMAL'] = add_floats(spec[:normals], 'VEC3', false) if spec[:normals]
      if spec[:skinned]
        count = spec[:positions].size / 3
        @accessors << { 'bufferView' => add_view(("\0" * (count * 4)).b), 'componentType' => UBYTE, 'count' => count, 'type' => 'VEC4' }
        prim['attributes']['JOINTS_0'] = @accessors.size - 1
        prim['attributes']['WEIGHTS_0'] = add_floats([1, 0, 0, 0] * count, 'VEC4', false)
      end
      prim['indices'] = add_indices(spec[:indices]) if spec[:indices]
      prim['mode'] = spec[:mode] unless spec[:mode].nil?
      prim['material'] = spec[:material] unless spec[:material].nil?
      prim['targets'] = spec[:targets].map { |t| { 'POSITION' => add_floats(t, 'VEC3', true) } } if spec[:targets]
      prim
    end

    def material(spec)
      out = { 'pbrMetallicRoughness' => { 'baseColorFactor' => spec[:color] || [1, 1, 1, 1],
                                          'metallicFactor' => spec[:metallic] || 0,
                                          'roughnessFactor' => spec[:roughness] || 1 } }
      out['name'] = spec[:name] if spec.key?(:name)
      out['emissiveFactor'] = spec[:emissive] if spec[:emissive]
      out
    end

    def node(spec)
      out = {}
      out['name'] = spec[:name] if spec.key?(:name)
      out['mesh'] = spec[:mesh] unless spec[:mesh].nil?
      out['children'] = spec[:children] if spec[:children]
      out['translation'] = spec[:translation] if spec[:translation]
      out['rotation'] = spec[:rotation] if spec[:rotation]
      out['scale'] = spec[:scale] if spec[:scale]
      out['skin'] = spec[:skin] unless spec[:skin].nil?
      out['camera'] = spec[:camera] unless spec[:camera].nil?
      out['extensions'] = { 'KHR_lights_punctual' => { 'light' => spec[:light] } } unless spec[:light].nil?
      out
    end

    def skin(spec)
      ibm = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] * spec[:joints].size
      out = { 'joints' => spec[:joints], 'inverseBindMatrices' => add_floats(ibm, 'MAT4', false) }
      out['skeleton'] = spec[:skeleton] unless spec[:skeleton].nil?
      out
    end

    def camera(spec)
      perspective = { 'yfov' => spec[:yfov] || 0.8, 'znear' => spec[:znear] || 0.05 }
      perspective['zfar'] = spec[:zfar] if spec[:zfar]
      out = { 'type' => 'perspective', 'perspective' => perspective }
      out['name'] = spec[:name] if spec.key?(:name)
      out
    end

    def light(spec)
      out = { 'type' => spec[:type], 'intensity' => spec[:intensity] || 1 }
      out['color'] = spec[:color] if spec[:color]
      out['name'] = spec[:name] if spec.key?(:name)
      out['spot'] = {} if spec[:type] == 'spot'
      out
    end

    def animation(spec)
      samplers = []
      channels = []
      spec[:channels].each do |ch|
        input = add_floats(ch[:times], 'SCALAR', !@faults[:no_animation_max])
        type = { 'rotation' => 'VEC4', 'weights' => 'SCALAR' }.fetch(ch[:path], 'VEC3')
        output = add_floats(ch[:values], type, false)
        samplers << { 'input' => input, 'output' => output, 'interpolation' => 'LINEAR' }
        channels << { 'sampler' => samplers.size - 1, 'target' => { 'node' => ch[:node], 'path' => ch[:path] } }
      end
      out = { 'samplers' => samplers, 'channels' => channels }
      out['name'] = spec[:name] if spec.key?(:name)
      out
    end

    def image(spec, index)
      bytes = spec[:mime] == 'image/png' ? GltfTestGlb.png(spec[:width], spec[:height], header_only: spec[:header_only]) : GltfTestGlb.jpeg_header(spec[:width], spec[:height])
      mime = spec[:declared_mime] || spec[:mime]
      return { 'uri' => 'texture.png', 'mimeType' => mime } if @faults[:image_uri] && index.zero?

      { 'bufferView' => add_view(bytes), 'mimeType' => mime }
    end

    # Header, JSON chunk (space-padded), BIN chunk (zero-padded).
    def assemble(text)
      json_length = (text.bytesize / 4.0).ceil * 4
      bin_padded = (@bin_length / 4.0).ceil * 4
      extra = @faults[:extra_chunk] ? 8 + 4 : 0
      total = 12 + 8 + json_length + (@bin_length.positive? ? 8 + bin_padded : 0) + extra
      out = [@faults[:bad_magic] ? 0x46546c68 : 0x46546c67, @faults[:bad_version] ? 1 : 2,
             @faults[:wrong_length] ? total + 4 : total, json_length, 0x4e4f534a].pack('V5')
      out << text << (' ' * (json_length - text.bytesize)).b
      if @bin_length.positive?
        out << [bin_padded, 0x004e4942].pack('V2')
        @parts.each { |part| out << part }
        out << ("\0" * (bin_padded - @bin_length)).b
      end
      out << [4, 0x12345678].pack('V2') << ("\0" * 4).b if @faults[:extra_chunk]
      out
    end
  end

  # --- scenes ------------------------------------------------------------------------------------

  # Rotation track about Y from identity to 90° and back over duration seconds.
  def wiggle(node, duration)
    { node: node, path: 'rotation', times: [0, duration / 2.0, duration], values: [0, 0, 0, 1, *ROT_Y_90, 0, 0, 0, 1] }
  end

  def morphed(material, base)
    n = base[:positions].size
    smile = Array.new(n) { |i| i % 3 == 1 ? 0.1 : 0 }
    blink = Array.new(n) { |i| (i % 3).zero? ? -0.05 : 0 }
    base.merge(material: material, targets: [smile, blink], skinned: true)
  end

  # The scene whose inspector summary equals the "summary" of manifest-cases.json.
  def fixture_scene
    {
      nodes: [
        { name: 'Root', children: [1, 3, 5, 6, 7, 8] },
        { name: 'Dancer', mesh: 0, skin: 0, children: [2] },
        { name: 'Hips', translation: [0, 0.5, 0] },
        { name: 'Speaker', mesh: 1, translation: [1.5, 0, 0], children: [4] },
        { name: 'Cone', mesh: 1, translation: [0, 0.5, 0.2], scale: [0.5, 0.5, 0.5] },
        { name: 'KeyLight', light: 0, translation: [1, 2, 2] },
        { name: 'Cam', camera: 0, translation: [0, 1, 4] },
        { name: 'Dup' },
        { name: 'Dup' }
      ],
      meshes: [
        { name: 'Body', primitives: [morphed(0, cube(1)), morphed(1, triangle)], target_names: %w[Smile Blink] },
        { name: 'SpeakerMesh', primitives: [cube(0.8, 2)] }
      ],
      materials: [
        { name: 'Skin', color: [0.9, 0.6, 0.5, 1] },
        { name: 'Outfit', color: [0.2, 0.4, 0.9, 1], emissive: [0.1, 0, 0] },
        { name: 'Neon', color: [1, 1, 1, 1], emissive: [1, 0.2, 0.6], roughness: 0.4, metallic: 0.1 },
        { name: 'Dup' },
        { name: 'Dup' }
      ],
      skins: [{ joints: [2] }],
      lights: [{ type: 'point', intensity: 3, name: 'Key' }],
      cameras: [{ yfov: 0.7, znear: 0.05, zfar: 100 }],
      animations: [
        { name: 'Idle', channels: [wiggle(2, 2)] },
        { name: 'Dance1', channels: [wiggle(2, 1.92)] },
        { name: 'Dance2', channels: [wiggle(2, 3.84)] },
        { name: 'Wave', channels: [{ node: 2, path: 'translation', times: [0, 1.5], values: [0, 0.5, 0, 0, 0.8, 0] }] },
        { name: 'Pump', channels: [{ node: 4, path: 'scale', times: [0, 0.25, 0.5], values: [0.5, 0.5, 0.5, 0.6, 0.6, 0.6, 0.5, 0.5, 0.5] }] },
        { name: 'Fan', channels: [wiggle(3, 4)] }
      ]
    }
  end

  def fixture_glb
    build(fixture_scene)
  end

  # manifest-cases.json (summary, valid, invalid), parsed.
  def manifest_cases
    @manifest_cases ||= JSON.parse(File.read(Rails.root.join('test', 'fixtures', 'files', 'visualizer_gltf', 'manifest-cases.json')))
  end
end
