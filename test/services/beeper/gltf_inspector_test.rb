require 'test_helper'

# Beeper::Gltf::Inspector and ImageHeader: the Ruby port of the shared core's GLB inspector. The
# cases mirror specs/gltf-visualizer/ts/__tests__/glb.test.ts; GLBs come from GltfTestGlb (the Ruby
# port of testGlb.ts).
class Beeper::GltfInspectorTest < ActiveSupport::TestCase
  G = GltfTestGlb
  LIMITS = Beeper::Gltf::LIMITS

  def limits(over)
    LIMITS.merge(over.stringify_keys)
  end

  def inspect_glb(bytes, lim = LIMITS)
    Beeper::Gltf::Inspector.call(bytes, lim)
  end

  def path_of(error)
    i = error.index(': ')
    i ? error[0...i] : error
  end

  def path_matches?(error, expected)
    path = path_of(error)
    path == expected || path.start_with?("#{expected}.") || path.start_with?("#{expected}[")
  end

  def expect_error(bytes, path, lim = LIMITS, message = nil)
    errors = inspect_glb(bytes, lim).errors
    hit = errors.find { |e| path_matches?(e, path) }
    assert hit, "no error at #{path}; got:\n  #{errors.join("\n  ")}"
    assert_match message, hit if message
    errors
  end

  def simple(**extra)
    { nodes: [{ name: 'A', mesh: 0 }], meshes: [{ name: 'M', primitives: [G.cube(1, 0)] }], materials: [{ name: 'Mat' }] }.merge(extra)
  end

  # --- a full valid scene ------------------------------------------------------------------------

  test 'a full valid scene: no errors; the summary equals the fixtures summary' do
    result = inspect_glb(G.fixture_glb)
    assert_equal [], result.errors
    assert_equal G.manifest_cases['summary'], result.summary
  end

  test 'a full valid scene: stats' do
    stats = inspect_glb(G.fixture_glb).stats
    assert_equal [9, 2, 5, 1, 1, 1, 2], stats.values_at('nodes', 'meshes', 'materials', 'skins', 'lights', 'cameras', 'morphTargets')
    # Body: cube 12 + triangle 1, once; SpeakerMesh: cube 12, instanced by Speaker and Cone.
    assert_equal [37, 27, 4], stats.values_at('triangles', 'vertices', 'drawCalls')
    assert_equal [1, 1, 2, 0, 0], stats['materialDrawCalls']
    assert_equal [['Idle', 2, 3], ['Dance1', 1.92, 3], ['Dance2', 3.84, 3], ['Wave', 1.5, 2], ['Pump', 0.5, 3], ['Fan', 4, 3]],
                 stats['clips'].map { |c| c.values_at('name', 'duration', 'keyframes') }
    assert_equal 17, stats['keyframes']
    assert_equal G.fixture_glb.bytesize, stats['bytes']
  end

  test 'a full valid scene: the fixture manifests validate against the inspected scene' do
    result = inspect_glb(G.fixture_glb)
    G.manifest_cases['valid'].each do |c|
      assert_equal [], Beeper::Manifests::VisualizerGltf.validate(c['manifest'], result.summary, stats: result.stats), c['name']
    end
  end

  # --- structural faults -------------------------------------------------------------------------

  test 'header' do
    expect_error(G.build(simple(faults: { bad_magic: true })), 'scene', LIMITS, /not a GLB/)
    expect_error(G.build(simple(faults: { bad_version: true })), 'scene', LIMITS, /version 1/)
    expect_error(G.build(simple(faults: { wrong_length: true })), 'scene', LIMITS, /header says/)
    expect_error(("\0" * 8).b, 'scene', LIMITS, /too short/)
    result = inspect_glb(G.build(simple(faults: { bad_magic: true })))
    assert_nil result.summary
    assert_nil result.stats
  end

  def json_only_glb(text)
    text = text.b
    [0x46546c67, 2, 20 + text.bytesize, text.bytesize, 0x4e4f534a].pack('V5') + text
  end

  test 'chunks and JSON' do
    expect_error(G.build(simple(faults: { extra_chunk: true })), 'scene', LIMITS, /after the BIN chunk|only one BIN/)
    bytes = G.build(simple)
    misaligned = bytes.dup
    misaligned[12, 4] = [bytes.byteslice(12, 4).unpack1('V') - 1].pack('V')
    expect_error(misaligned, 'scene', LIMITS, /multiple of 4/)
    # A JSON chunk that is valid UTF-8 but not an object.
    glb = json_only_glb('[1, 2]  ')
    expect_error(glb, 'scene', LIMITS, /not an object/)
    glb.setbyte(20, 0xc0) # overlong lead byte
    expect_error(glb, 'scene', LIMITS, /UTF-8/)
  end

  test 'the JSON chunk must be strict UTF-8 (overlongs, surrogates, truncation, > U+10FFFF, stray bytes)' do
    [[0xc0, 0x80], [0xed, 0xa0, 0x80], [0xe2, 0x82], [0xf4, 0x90, 0x80, 0x80], [0x80], [0xff]].each do |bad|
      text = "{\"a\":\"".b + bad.pack('C*') + '"}'.b
      text << (' ' * ((4 - (text.bytesize % 4)) % 4)).b
      expect_error(json_only_glb(text), 'scene', LIMITS, /UTF-8/)
    end
    good = '{"asset":{"version":"2.0"},"nodes":[{"name":"Tänzer € 😀 名前"}]}'.b
    good << (' ' * ((4 - (good.bytesize % 4)) % 4)).b
    result = inspect_glb(json_only_glb(good))
    assert_equal [], result.errors
    assert_equal ['Tänzer € 😀 名前'], result.summary['nodes']
  end

  test 'asset version, extensions' do
    expect_error(G.build(simple(edit_json: ->(j) { j['asset']['version'] = '1.0' })), 'scene.asset.version')
    draco = expect_error(G.build(simple(extensions_used: ['KHR_draco_mesh_compression'])), 'scene.extensionsUsed', LIMITS, /Draco needs a WebAssembly decoder/)
    assert_equal 1, draco.size
    expect_error(G.build(simple(extensions_used: ['EXT_texture_webp'])), 'scene.extensionsUsed', LIMITS, /WebP/)
    expect_error(G.build(simple(extensions_used: ['EXT_foo'])), 'scene.extensionsUsed', LIMITS, /EXT_foo: not supported/)
    expect_error(G.build(simple(extensions_used: ['KHR_texture_transform'], extensions_required: ['KHR_materials_unlit'])), 'scene.extensionsRequired')
    assert_equal [], inspect_glb(G.build(simple(extensions_used: %w[KHR_texture_transform KHR_mesh_quantization]))).errors
  end

  test 'buffers, bufferViews, accessors' do
    expect_error(G.build(simple(faults: { external_buffer_uri: true })), 'scene.buffers[0].uri')
    expect_error(G.build(simple(edit_json: ->(j) { j['buffers'] << { 'byteLength' => 4 } })), 'scene.buffers')
    expect_error(G.build(simple(edit_json: ->(j) { j['buffers'][0]['byteLength'] += 64 })), 'scene.buffers[0].byteLength')
    expect_error(G.build(simple(edit_json: ->(j) { j['bufferViews'][0]['byteLength'] += 4096 })), 'scene.bufferViews[0]')
    expect_error(G.build(simple(faults: { accessor_out_of_bounds: 0 })), 'scene.accessors[0]', LIMITS, /bufferView 0/)
    expect_error(G.build(simple(edit_json: ->(j) { j['accessors'][0]['componentType'] = 5124 })), 'scene.accessors[0].componentType')
    expect_error(G.build(simple(edit_json: ->(j) { j['accessors'][0]['type'] = 'VEC5' })), 'scene.accessors[0].type')
    expect_error(G.build(simple(edit_json: ->(j) { j['meshes'][0]['primitives'][0]['attributes']['POSITION'] = 99 })),
                 'scene.meshes[0].primitives[0].attributes.POSITION')
  end

  test 'accessor element size has no matrix column padding' do
    # A MAT3 of UNSIGNED_BYTE is 9 bytes here (the glTF spec would pad its columns to 12): four
    # of them fit the cube's 36-byte index bufferView exactly; a fifth does not.
    mat3 = lambda do |count|
      G.build(simple(edit_json: lambda { |j|
        view = j['accessors'][j['meshes'][0]['primitives'][0]['indices']]['bufferView']
        j['accessors'] << { 'bufferView' => view, 'componentType' => 5121, 'count' => count, 'type' => 'MAT3' }
      }))
    end
    assert_equal [], inspect_glb(mat3.call(4)).errors
    expect_error(mat3.call(5), 'scene.accessors[3]', LIMITS, /needs bytes 0..45 of bufferView 2, which has 36/)
  end

  test 'sparse accessors are bounds-checked' do
    sparse = lambda do |indices_offset|
      G.build(simple(edit_json: lambda { |j|
        # Reuse the index bufferView (36 bytes) for both sparse arrays.
        idx_view = j['accessors'][j['meshes'][0]['primitives'][0]['indices']]['bufferView']
        j['accessors'][0]['sparse'] = { 'count' => 4, 'indices' => { 'bufferView' => idx_view, 'byteOffset' => indices_offset, 'componentType' => 5121 },
                                        'values' => { 'bufferView' => 0, 'byteOffset' => 0 } }
      }))
    end
    assert_equal [], inspect_glb(sparse.call(0)).errors
    expect_error(sparse.call(34), 'scene.accessors[0].sparse.indices')
  end

  test 'sparse values are bounds-checked too' do
    # Accessor 0 is the cube's POSITION (VEC3 float, 12-byte elements); values sit in the 36-byte
    # index bufferView: 3 elements fit (36 bytes), 4 do not.
    sparse = lambda do |count|
      G.build(simple(edit_json: lambda { |j|
        idx_view = j['accessors'][j['meshes'][0]['primitives'][0]['indices']]['bufferView']
        j['accessors'][0]['sparse'] = { 'count' => count, 'indices' => { 'bufferView' => idx_view, 'componentType' => 5121 },
                                        'values' => { 'bufferView' => idx_view } }
      }))
    end
    assert_equal [], inspect_glb(sparse.call(3)).errors
    expect_error(sparse.call(4), 'scene.accessors[0].sparse.values', LIMITS, /needs bytes 0..48 of bufferView 2, which has 36/)
    expect_error(G.build(simple(edit_json: ->(j) { j['accessors'][0]['sparse'] = { 'count' => 1, 'indices' => { 'bufferView' => 0, 'componentType' => 5121 } } })),
                 'scene.accessors[0].sparse.values', LIMITS, /needs a bufferView/)
    expect_error(G.build(simple(edit_json: ->(j) { j['accessors'][0]['sparse'] = { 'count' => 1, 'indices' => { 'bufferView' => 0, 'componentType' => 5121 }, 'values' => { 'bufferView' => 0, 'byteOffset' => -4 } } })),
                 'scene.accessors[0].sparse.values.byteOffset')
  end

  test 'images: embedded, PNG/JPEG, magic, header size limits' do
    expect_error(G.build(simple(images: [{ mime: 'image/png', width: 2, height: 2 }], faults: { image_uri: true })), 'scene.images[0].uri')
    expect_error(G.build(simple(images: [{ mime: 'image/png', width: 2, height: 2, declared_mime: 'image/webp' }])), 'scene.images[0].mimeType')
    expect_error(G.build(simple(images: [{ mime: 'image/png', width: 2, height: 2, declared_mime: 'image/jpeg' }])), 'scene.images[0]', LIMITS, /not a JPEG/)
    expect_error(G.build(simple(images: [{ mime: 'image/png', width: 4096, height: 16, header_only: true }])), 'scene.images[0]', LIMITS, /4096×16 exceeds 2048×2048/)
    expect_error(G.build(simple(images: [{ mime: 'image/png', width: 2048, height: 2048, header_only: true }, { mime: 'image/jpeg', width: 2048, height: 2048 }])),
                 'scene.images', limits(maxTexturePixels: 2048 * 2048), /pixels in total/)
    expect_error(G.build(simple(edit_json: ->(j) { j['images'] = [{ 'mimeType' => 'image/png' }] })), 'scene.images[0]', LIMITS, /bufferView/)
  end

  test 'image stats from PNG IHDR and JPEG SOF' do
    result = inspect_glb(G.build(simple(images: [{ mime: 'image/png', width: 3, height: 5 }, { mime: 'image/jpeg', width: 640, height: 480 }])))
    assert_equal [], result.errors
    assert_equal [[0, 'image/png', 3, 5], [1, 'image/jpeg', 640, 480]], result.stats['images'].map { |i| i.values_at('index', 'mime', 'width', 'height') }
    assert_equal G.png(3, 5).bytesize, result.stats['images'][0]['bytes']
    assert_equal 15 + (640 * 480), result.stats['texturePixels']
  end

  test 'animations: input max required, duration limit' do
    anim = lambda do |seconds, faults = {}|
      G.build(simple(animations: [{ name: 'Spin', channels: [{ node: 0, path: 'translation', times: [0, seconds], values: [0, 0, 0, 1, 0, 0] }] }], faults: faults))
    end
    expect_error(anim.call(1, no_animation_max: true), 'scene.animations[0].samplers[0].input', LIMITS, /no max/)
    expect_error(anim.call(121), 'scene.animations[0]', LIMITS, /121 s long/)
    assert_equal [], inspect_glb(anim.call(120)).errors
  end

  # --- counts against limits ---------------------------------------------------------------------

  {
    { maxNodes: 8 } => ['scene.nodes', /\Ascene\.nodes: 9 nodes; the limit is 8\z/],
    { maxMeshes: 1 } => ['scene.meshes', /: 2 meshes; the limit is 1\z/],
    { maxMaterials: 4 } => ['scene.materials', /: 5 materials; the limit is 4\z/],
    { maxTriangles: 36 } => ['scene', /\Ascene: 37 triangles; the limit is 36\z/],
    { maxVertices: 26 } => ['scene', /\Ascene: 27 vertices; the limit is 26\z/],
    { maxDrawCalls: 3 } => ['scene', /\Ascene: 4 draw calls; the limit is 3\z/],
    { maxAnimations: 5 } => ['scene.animations', /: 6 animations; the limit is 5\z/],
    { maxKeyframes: 16 } => ['scene.animations', /: 17 keyframes; the limit is 16\z/],
    { maxAnimationSeconds: 3 } => ['scene.animations[5]', /: 4 s long; the limit is 3 s\z/],
    { maxMorphTargets: 1 } => ['scene.meshes[0]', /: 2 morph targets; the limit is 1\z/],
    { maxSkins: 0 } => ['scene.skins', /\Ascene\.skins: 1 skins; the limit is 0\z/],
    { maxJoints: 0 } => ['scene.skins[0].joints', /: 1 joints; the limit is 0\z/],
    { maxLights: 0 } => ['scene.extensions.KHR_lights_punctual.lights', /: 1 lights; the limit is 0\z/],
    { maxCameras: 0 } => ['scene.cameras', /\Ascene\.cameras: 1 cameras; the limit is 0\z/],
    { glbMaxBytes: 100 } => ['scene', /\Ascene: the file is [\d.]+ MB; the limit is 0\.0 MB\z/],
    { jsonChunkMaxBytes: 100 } => ['scene', /\Ascene: the JSON chunk is [\d.]+ MB; the limit is 0\.0 MB\z/]
  }.each do |over, (path, message)|
    test "counts: #{over.keys.first} → #{path}" do
      expect_error(G.fixture_glb, path, limits(over), message)
    end
  end

  test 'counts: exactly at the limits is fine' do
    at = limits(maxNodes: 9, maxMeshes: 2, maxMaterials: 5, maxTriangles: 37, maxVertices: 27, maxDrawCalls: 4, maxAnimations: 6,
                maxKeyframes: 17, maxMorphTargets: 2, maxSkins: 1, maxJoints: 1, maxLights: 1, maxCameras: 1)
    assert_equal [], inspect_glb(G.fixture_glb, at).errors
  end

  # --- triangles, vertices, draw calls -----------------------------------------------------------

  test 'modes, indices vs positions, instancing' do
    strip = { positions: [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 2, 0, 0], indices: [0, 1, 2, 3, 4], mode: 5, material: 0 }
    fan = { positions: [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0], mode: 6 }
    lines = { positions: [0, 0, 0, 1, 0, 0], mode: 1, material: 1 }
    result = inspect_glb(G.build(nodes: [{ name: 'a', mesh: 0 }, { name: 'b', mesh: 0 }, { name: 'c', mesh: 0 }, { name: 'd', mesh: 1 }],
                                 meshes: [{ name: 'Cube', primitives: [G.cube(1, 0)] }, { name: 'Mixed', primitives: [strip, fan, lines, G.triangle(0)] }],
                                 materials: [{ name: 'A' }, { name: 'B' }]))
    assert_equal [], result.errors
    # Cube ×3: 36 tris, 24 verts, 3 draws. Mixed ×1: strip 3 + fan 2 + lines 0 + triangle 1; 5+4+2+3 verts; 4 draws.
    assert_equal [42, 38, 7], result.stats.values_at('triangles', 'vertices', 'drawCalls')
    assert_equal [5, 1], result.stats['materialDrawCalls']
  end

  test 'a mesh no node uses costs nothing' do
    stats = inspect_glb(G.build(nodes: [{ name: 'empty' }], meshes: [{ primitives: [G.cube] }])).stats
    assert_equal [0, 0], stats.values_at('triangles', 'drawCalls')
  end

  # --- image headers -----------------------------------------------------------------------------

  test 'image headers: PNG and JPEG sizes, sniffing, bad input' do
    header = Beeper::Gltf::ImageHeader
    assert_equal({ width: 7, height: 9 }, header.size(G.png(7, 9), 'image/png'))
    assert_equal({ width: 3000, height: 20 }, header.size(G.png(3000, 20, header_only: true), 'image/png'))
    assert_equal({ width: 1920, height: 1080 }, header.size(G.jpeg_header(1920, 1080), 'image/jpeg'))
    assert_nil header.size(G.png(2, 2), 'image/jpeg')
    assert_equal 'image/jpeg', header.sniff(G.jpeg_header(1, 1))
    assert_nil header.sniff([1, 2, 3].pack('C*'))
    # Progressive (SOF2) after a DQT-like segment, with fill bytes before the marker.
    prog = [0xff, 0xd8, 0xff, 0xdb, 0x00, 0x04, 0x00, 0x00, 0xff, 0xff, 0xc2, 0x00, 0x11, 0x08, 0x00, 0x20, 0x00, 0x40, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1].pack('C*')
    assert_equal({ width: 64, height: 32 }, header.size(prog, 'image/jpeg'))
    # SOS before any SOF, or a DHT (C4) only: no size.
    assert_nil header.size([0xff, 0xd8, 0xff, 0xda, 0x00, 0x02].pack('C*'), 'image/jpeg')
    assert_nil header.size([0xff, 0xd8, 0xff, 0xc4, 0x00, 0x02, 0xff, 0xd9].pack('C*'), 'image/jpeg')
  end

  test 'the generated PNG is well formed (IHDR, inflatable IDAT)' do
    png = G.png(2, 2)
    assert_equal 13, png.byteslice(8, 4).unpack1('N')
    assert_equal 'IHDR', png.byteslice(12, 4)
    idat_length = png.byteslice(33, 4).unpack1('N')
    assert_equal 2 * (1 + (2 * 4)), Zlib::Inflate.inflate(png.byteslice(41, idat_length)).bytesize
  end

  test 'a UTF-8 String of GLB bytes is read as binary' do
    bytes = G.build(simple).dup.force_encoding(Encoding::UTF_8)
    assert_equal [], inspect_glb(bytes).errors
  end

  # --- image trailers (glb.test.ts "image trailers") ----------------------------------------------

  def trailer_png
    G.png(4, 4)
  end

  def trailer_jpeg
    G.jpeg_header(640, 480)
  end

  def one_image(data, mime)
    inspect_glb(G.images_on_one_view(data, 1, mime)).errors
  end

  def cat(bytes, tail)
    bytes + tail.pack('C*')
  end

  PNG_CUT = 'scene.images[0]: the PNG is cut short (no IEND)'.freeze
  JPEG_CUT = 'scene.images[0]: the JPEG is cut short (no EOI)'.freeze

  test 'image trailers: complete PNG and JPEG pass and are counted' do
    header = Beeper::Gltf::ImageHeader
    assert_equal [0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82], trailer_png.byteslice(-12, 12).bytes
    assert_equal [0xff, 0xd9], trailer_jpeg.byteslice(-2, 2).bytes
    assert header.trailer?(trailer_png, 'image/png')
    assert header.trailer?(trailer_jpeg, 'image/jpeg')
    assert header.trailer?(G.png(3000, 20, header_only: true), 'image/png')
    assert_equal [], one_image(trailer_png, 'image/png')
    result = inspect_glb(G.images_on_one_view(trailer_jpeg, 1))
    assert_equal [], result.errors
    assert_equal [[640, 480]], result.stats['images'].map { |i| i.values_at('width', 'height') }
  end

  test 'image trailers: PNG without IEND' do
    assert_equal [PNG_CUT], inspect_glb(G.build(simple(images: [{ mime: 'image/png', width: 4, height: 4, truncated: true }]))).errors
    assert_equal [PNG_CUT], one_image(trailer_png.byteslice(0, trailer_png.bytesize - 1), 'image/png') # one CRC byte short
    assert_equal [PNG_CUT], one_image(trailer_png.byteslice(0, trailer_png.bytesize - 30), 'image/png') # inside IDAT
    bad_crc = trailer_png.dup
    bad_crc.setbyte(bad_crc.bytesize - 1, bad_crc.getbyte(bad_crc.bytesize - 1) ^ 1)
    assert_equal [PNG_CUT], one_image(bad_crc, 'image/png')
    # Cut-short images add no stats or pixels.
    stats = inspect_glb(G.images_on_one_view(trailer_png.byteslice(0, trailer_png.bytesize - 1), 1, 'image/png')).stats
    assert_equal [], stats['images']
    assert_equal 0, stats['texturePixels']
  end

  test 'image trailers: JPEG without EOI' do
    assert_equal [JPEG_CUT], inspect_glb(G.build(simple(images: [{ mime: 'image/jpeg', width: 8, height: 8, truncated: true }]))).errors
    assert_equal [JPEG_CUT], one_image(G.jpeg_header(8, 8, no_eoi: true), 'image/jpeg')
    assert_equal [JPEG_CUT], one_image(trailer_jpeg.byteslice(0, trailer_jpeg.bytesize - 1), 'image/jpeg')
    assert_equal [JPEG_CUT], one_image(cat(trailer_jpeg, [0x12]), 'image/jpeg') # junk after EOI
  end

  test 'image trailers: an unreadable header is reported instead of the trailer' do
    assert_equal ["scene.images[0]: can't read the PNG header"], one_image(G.png(4, 4).byteslice(0, 20), 'image/png')
  end

  test 'image trailers: padding: up to 3 trailing 0x00 bytes after the trailer, nothing else' do
    [1, 2, 3].each do |k|
      zeros = Array.new(k, 0)
      assert_equal [], one_image(cat(trailer_png, zeros), 'image/png'), "PNG + #{k}"
      assert_equal [], one_image(cat(trailer_jpeg, zeros), 'image/jpeg'), "JPEG + #{k}"
    end
    assert_equal [PNG_CUT], one_image(cat(trailer_png, [0, 0, 0, 0]), 'image/png')
    assert_equal [JPEG_CUT], one_image(cat(trailer_jpeg, [0, 0, 0, 0]), 'image/jpeg')
    assert_equal [PNG_CUT], one_image(cat(trailer_png, [0x20]), 'image/png')
    assert_equal [JPEG_CUT], one_image(cat(trailer_jpeg, [0, 0xff]), 'image/jpeg')
  end

  test 'image trailers: the trailer result is memoised per bufferView like the header' do
    errors = inspect_glb(G.images_on_one_view(G.jpeg_header(8, 8, no_eoi: true), 3)).errors
    assert_equal((0..2).map { |i| "scene.images[#{i}]: the JPEG is cut short (no EOI)" }, errors)
  end

  test 'image trailers: read in place at an offset, the bytes after the view do not count' do
    header = Beeper::Gltf::ImageHeader
    inside = 'ab'.b + G.jpeg_header(8, 8, no_eoi: true) + [0xff, 0xd9].pack('C*')
    refute header.trailer?(inside, 'image/jpeg', 2, inside.bytesize - 4) # the EOI lies past the view
    assert header.trailer?(inside, 'image/jpeg', 2, inside.bytesize - 2)
    refute header.trailer?(trailer_png, 'image/webp')
    refute header.trailer?(''.b, 'image/jpeg')
  end

  # --- work bounds against crafted files (glb.test.ts "work bounds") ------------------------------
  # Time bounds are the TS ones; Ruby is slower than V8, so each is doubled.

  MAX_ERRORS = Beeper::Gltf::Inspector::MAX_ERRORS
  BIG_JSON = { jsonChunkMaxBytes: 4 << 20 }.freeze

  def elapsed_ms
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
  end

  test 'work bounds: the constants are the TS ones' do
    inspector = Beeper::Gltf::Inspector
    assert_equal [100, 4, 65_536, 100, 512],
                 [inspector::MAX_ERRORS, inspector::SKIP_FACTOR, inspector::MAX_UNBOUNDED_ARRAY, inspector::MAX_JSON_DEPTH, inspector::MAX_JPEG_MARKERS]
  end

  test 'work bounds: 50k images on one bufferView: one count error, no header parsing' do
    glb = G.images_on_one_view(G.jpeg_header(8, 8), 50_000)
    result = nil
    ms = elapsed_ms { result = inspect_glb(glb, limits(BIG_JSON)) }
    assert_equal ['scene.images: 50000 images; the limit is 16'], result.errors
    assert_equal [], result.stats['images']
    assert result.capped
    assert_operator ms, :<, 4000
  end

  test 'work bounds: over maxImages but under 4× the limit: only the first maxImages are inspected' do
    result = inspect_glb(G.images_on_one_view(G.jpeg_header(8, 8), 40))
    assert_equal ['scene.images: 40 images; the limit is 16'], result.errors
    assert_equal (0...16).to_a, result.stats['images'].map { |i| i['index'] }
    assert_equal 16 * 64, result.stats['texturePixels']
    refute result.capped
  end

  test 'work bounds: a header is parsed once per bufferView (a 1 MB fill-byte run × 50k images stays fast)' do
    slow = ("\xff".b * (1 << 20))
    slow.setbyte(1, 0xd8) # SOI, then fill bytes to the end: one parse walks the whole view
    glb = G.images_on_one_view(slow, 50_000)
    errors = nil
    ms = elapsed_ms { errors = inspect_glb(glb, limits(BIG_JSON.merge(maxImages: 100_000))).errors }
    assert_operator ms, :<, 6000
    assert_equal MAX_ERRORS + 1, errors.size
    assert_equal "scene.images[0]: can't read the JPEG header", errors[0]
    assert_equal "scene: …and #{50_000 - MAX_ERRORS} more problems", errors[MAX_ERRORS]
  end

  test 'work bounds: the JPEG marker scan stops after MAX_JPEG_MARKERS markers' do
    header = Beeper::Gltf::ImageHeader
    assert_equal({ width: 640, height: 480 }, header.size(G.jpeg_chain(511, 640, 480), 'image/jpeg')) # SOF is marker 512
    assert_nil header.size(G.jpeg_chain(512, 640, 480), 'image/jpeg') # SOF would be marker 513
    assert_equal ["scene.images[0]: can't read the JPEG header"], inspect_glb(G.images_on_one_view(G.jpeg_chain(100_000, 64, 64), 1)).errors
    assert_equal [], inspect_glb(G.images_on_one_view(G.jpeg_chain(511, 64, 64), 1)).errors
  end

  # glb.ts's JPEG scan, byte by byte (fill bytes stepped one at a time), to check the Ruby
  # version's String#index fill skip against.
  def reference_jpeg_size(bytes, start, n)
    b = ->(i) { bytes.getbyte(start + i) }
    return nil unless n >= 3 && b.call(0) == 0xff && b.call(1) == 0xd8 && b.call(2) == 0xff

    i = 2
    markers = 0
    while i + 1 < n
      return nil if b.call(i) != 0xff
      return nil if (markers += 1) > 512

      m = b.call(i + 1)
      while m == 0xff && i + 2 < n
        i += 1
        m = b.call(i + 1)
      end
      i += 2
      next if m == 0xd8 || m == 0x01 || (0xd0..0xd7).cover?(m)
      return nil if [0xd9, 0xda].include?(m) || i + 2 > n

      len = (b.call(i) << 8) | b.call(i + 1)
      return nil if len < 2

      if Beeper::Gltf::ImageHeader.jpeg_sof?(m)
        return nil if i + 7 > n

        h = (b.call(i + 3) << 8) | b.call(i + 4)
        w = (b.call(i + 5) << 8) | b.call(i + 6)
        return w.positive? && h.positive? ? { width: w, height: h } : nil
      end
      i += len
    end
    nil
  end

  test 'work bounds: the fill-byte skip stops exactly where the byte-by-byte scan does' do
    sof = [0xc0, 0x00, 0x11, 0x08, 0x00, 0x20, 0x00, 0x40, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]
    cases = []
    [0, 1, 2, 5, 65_533, 65_534, 65_535, 65_536, 131_072, 140_000].each do |fill| # and across 64 KB chunks
      cases << ([0xff, 0xd8, 0xff] + ([0xff] * fill) + sof)                   # fill before SOF
      cases << ([0xff, 0xd8, 0xff, 0xe0, 0, 2, 0xff] + ([0xff] * fill) + sof) # after an APP0
      cases << ([0xff, 0xd8] + ([0xff] * (fill + 1)))                          # fill to the end
      cases << ([0xff, 0xd8, 0xff] + ([0xff] * fill) + [0xd9])                 # fill, then EOI
    end
    srand(1234)
    40.times { cases << ([0xff, 0xd8, 0xff] + Array.new(rand(4..40)) { [0xff, 0xff, 0xc0, 0xd8, 0x00, 0x02, rand(256)].sample }) }
    header = Beeper::Gltf::ImageHeader
    sized = 0
    cases.each do |list|
      data = list.pack('C*')
      # Whole, inside a larger buffer, and cut short inside a run of 0xFF that continues past the view.
      [[data, 0, data.bytesize], [('ab'.b + data + ("\xff".b * 9)), 2, data.bytesize], [(data + ("\xff".b * 9)), 0, data.bytesize]].each do |bytes, start, n|
        expected = reference_jpeg_size(bytes, start, n)
        actual = header.size(bytes, 'image/jpeg', start, n)
        expected.nil? ? assert_nil(actual, list.inspect) : assert_equal(expected, actual, list.inspect)
        sized += 1 if expected
      end
    end
    assert_operator sized, :>=, 24 # the SOF cases did yield sizes
  end

  test 'work bounds: 16 images on 16 bufferViews over one 18 MB run of 0xFF stay fast' do
    run = "\xff".b * (18 << 20)
    run.setbyte(1, 0xd8)
    json = { 'asset' => { 'version' => '2.0' }, 'buffers' => [{ 'byteLength' => run.bytesize }],
             'bufferViews' => Array.new(16) { |i| { 'buffer' => 0, 'byteLength' => run.bytesize - i } },
             'images' => Array.new(16) { |i| { 'bufferView' => i, 'mimeType' => 'image/jpeg' } } }
    glb = G.raw_glb(json, run)
    errors = nil
    ms = elapsed_ms { errors = inspect_glb(glb).errors }
    assert_equal Array.new(16) { |i| "scene.images[#{i}]: can't read the JPEG header" }, errors
    assert_operator ms, :<, 2000
  end

  test 'work bounds: image headers are read in place, at an offset into the file' do
    bytes = ('junk'.b * 3) + G.png(7, 9) + G.jpeg_header(30, 20)
    header = Beeper::Gltf::ImageHeader
    assert_equal 'image/png', header.sniff(bytes, 12, G.png(7, 9).bytesize)
    assert_equal({ width: 7, height: 9 }, header.size(bytes, 'image/png', 12, G.png(7, 9).bytesize))
    jpeg_at = 12 + G.png(7, 9).bytesize
    assert_equal({ width: 30, height: 20 }, header.size(bytes, 'image/jpeg', jpeg_at, G.jpeg_header(30, 20).bytesize))
    assert_nil header.size(bytes, 'image/jpeg', jpeg_at, 3) # cut short
  end

  test 'work bounds: 700k empty bufferViews: one early error, the list stays bounded' do
    glb = G.build(simple(edit_json: ->(j) { j['bufferViews'] = Array.new(700_000) { {} } }))
    errors = nil
    ms = elapsed_ms { errors = inspect_glb(glb, limits(BIG_JSON)).errors }
    assert_operator ms, :<, 6000
    assert_equal 'scene.bufferViews: 700000 bufferViews; the limit is 65536', errors[0]
    assert_equal 1, errors.count { |e| path_matches?(e, 'scene.bufferViews') }
    assert_operator errors.size, :<=, MAX_ERRORS + 1
  end

  test 'work bounds: the error list keeps MAX_ERRORS entries, then one summary line' do
    bad = ->(k) { G.build(simple(edit_json: ->(j) { j['bufferViews'] += Array.new(k) { {} } })) }
    at = inspect_glb(bad.call(100))
    assert_equal 100, at.errors.size
    assert(at.errors.all? { |e| e.end_with?(' no such buffer') })
    refute at.capped
    one = inspect_glb(bad.call(101))
    assert_equal 101, one.errors.size
    assert_equal 'scene: …and 1 more problem', one.errors[100]
    assert one.capped
    many = inspect_glb(bad.call(300)).errors
    assert_equal 101, many.size
    assert_equal 'scene: …and 200 more problems', many[100]
  end

  test 'work bounds: arrays with a limit are skipped past 4× it; the count error is the same either way' do
    nodes = ->(k) { G.build(simple(edit_json: ->(j) { j['nodes'] = Array.new(k) { { 'name' => 'N' } } })) }
    at = inspect_glb(nodes.call(4 * 512))
    assert_equal ['scene.nodes: 2048 nodes; the limit is 512'], at.errors
    assert_equal 2048, at.summary['nodes'].size
    refute at.capped
    over = inspect_glb(nodes.call((4 * 512) + 1))
    assert_equal ['scene.nodes: 2049 nodes; the limit is 512'], over.errors
    assert_equal [], over.summary['nodes']
    assert_equal 0, over.stats['nodes']
    assert over.capped
    lights = inspect_glb(G.build(simple(edit_json: ->(j) { j['extensions'] = { 'KHR_lights_punctual' => { 'lights' => Array.new(17) { { 'type' => 'point' } } } } })))
    assert_equal ['scene.extensions.KHR_lights_punctual.lights: 17 lights; the limit is 4'], lights.errors
  end

  test 'work bounds: every limited array is skipped past 4× its limit, references into it then miss' do
    {
      'meshes' => 128, 'materials' => 32, 'images' => 16, 'animations' => 32, 'skins' => 4, 'cameras' => 4
    }.each do |key, limit|
      result = inspect_glb(G.build(simple(edit_json: ->(j) { j[key] = Array.new((4 * limit) + 1) { {} } })))
      assert_equal "scene.#{key}: #{(4 * limit) + 1} #{key}; the limit is #{limit}", result.errors[0], key
      assert_equal 1, result.errors.count { |e| path_matches?(e, "scene.#{key}") }, key
    end
    # The node's mesh 0 now resolves as missing.
    meshes = inspect_glb(G.build(simple(edit_json: ->(j) { j['meshes'] = Array.new(513) { j['meshes'][0] } })))
    assert_includes meshes.errors, 'scene.nodes[0].mesh: no such mesh'
    assert_equal [], meshes.summary['meshes']
  end

  test 'work bounds: arrays without a limit are capped at 65536' do
    %w[accessors samplers textures scenes buffers extensionsUsed].each do |key|
      errors = inspect_glb(G.build(simple(edit_json: ->(j) { j[key] = Array.new(65_537, 0) }))).errors
      assert_equal "scene.#{key}: 65537 #{key}; the limit is 65536", errors[0], key
      assert_equal 1, errors.count { |e| path_matches?(e, "scene.#{key}") }, key
    end
    assert_equal [], inspect_glb(G.build(simple(edit_json: ->(j) { j['textures'] = Array.new(65_536) { {} } }))).errors
    # Top-level samplers, textures and scenes that aren't arrays: no error, as before.
    assert_equal [], inspect_glb(G.build(simple(edit_json: ->(j) { j['samplers'] = 'x' }))).errors
  end

  test 'work bounds: extensionsRequired is checked in linear time' do
    names = Array.new(60_000) { |i| "X_#{i}" }
    glb = G.build(simple(edit_json: ->(j) { j['extensionsUsed'] = names; j['extensionsRequired'] = names + ['Y'] }))
    errors = nil
    ms = elapsed_ms { errors = inspect_glb(glb).errors }
    assert_operator ms, :<, 4000
    assert_equal 'scene: …and 59901 more problems', errors.last # 60000 unsupported + 1 not listed, 100 kept
  end

  test 'work bounds: a non-string extensionsRequired entry is never listed' do
    errors = inspect_glb(G.build(simple(edit_json: ->(j) { j['extensionsUsed'] = ['KHR_texture_transform']; j['extensionsRequired'] = [7, nil, ['KHR_texture_transform']] }))).errors
    assert_equal ['scene.extensionsRequired: 7 is not listed in extensionsUsed',
                  'scene.extensionsRequired: null is not listed in extensionsUsed',
                  'scene.extensionsRequired: KHR_texture_transform is not listed in extensionsUsed'], errors
  end

  test 'work bounds: per-mesh primitives past 4 × maxDrawCalls, morph names past 4 × maxMorphTargets, samplers past 65536' do
    prims = ->(k) { G.build(simple(edit_json: ->(j) { j['meshes'][0]['primitives'] = Array.new(k, j['meshes'][0]['primitives'][0]) })) }
    lim = limits(maxDrawCalls: 2)
    assert_equal ['scene.meshes[0].primitives: 9 primitives; the limit is 2'], inspect_glb(prims.call(9), lim).errors
    assert_equal ['scene: 8 draw calls; the limit is 2'], inspect_glb(prims.call(8), lim).errors

    targets = ->(k) { G.build(simple(edit_json: ->(j) { j['meshes'][0]['primitives'][0]['targets'] = Array.new(k) { {} } })) }
    one = limits(maxMorphTargets: 1)
    four = inspect_glb(targets.call(4), one)
    assert_equal ['scene.meshes[0]: 4 morph targets; the limit is 1'], four.errors
    assert_equal ['', '', '', ''], four.summary['meshes'][0]['morphs']
    five = inspect_glb(targets.call(5), one)
    assert_equal ['scene.meshes[0]: 5 morph targets; the limit is 1'], five.errors
    assert_equal [], five.summary['meshes'][0]['morphs']
    assert_equal 5, five.stats['morphTargets']

    samplers = inspect_glb(G.build(simple(edit_json: ->(j) { j['animations'] = [{ 'channels' => [], 'samplers' => Array.new(65_537) { {} } }] })))
    assert_equal ['scene.animations[0].samplers: 65537 samplers; the limit is 65536'], samplers.errors
  end

  test 'work bounds: JSON nested deeper than 100 is refused, as Ruby JSON does' do
    deep = ->(depth) { G.build(simple(edit_json: ->(j) { j['extras'] = G.nest(depth - 1) })) } # the root object is depth 1
    assert_equal [], inspect_glb(deep.call(100)).errors
    refused = inspect_glb(deep.call(101))
    assert_equal ['scene: JSON nested too deeply'], refused.errors
    assert_nil refused.summary
    assert_nil refused.stats
    # Brackets inside strings don't count, escaped quotes don't end a string.
    assert_equal [], inspect_glb(G.build(simple(edit_json: ->(j) { j['extras'] = { 's' => ('"\\' * 3) + ('[' * 500) } }))).errors
    too_deep = Beeper::Gltf::Inspector.method(:json_too_deep?)
    refute too_deep.call(('[' * 100) + (']' * 100))
    assert too_deep.call('[' * 101) # decided before parsing: invalid JSON too
    refute too_deep.call('{"a":"[[[[\\"[[["}')
    assert too_deep.call('[{}]', 1)
    refute too_deep.call('["\\') # a backslash ending the text
    assert_equal ['scene: JSON nested too deeply'], inspect_glb(json_only_glb(('[' * 101).ljust(104))).errors
  end
end
