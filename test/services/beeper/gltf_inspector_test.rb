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
    { maxNodes: 8 } => 'scene.nodes',
    { maxMeshes: 1 } => 'scene.meshes',
    { maxMaterials: 4 } => 'scene.materials',
    { maxTriangles: 36 } => 'scene',
    { maxVertices: 26 } => 'scene',
    { maxDrawCalls: 3 } => 'scene',
    { maxAnimations: 5 } => 'scene.animations',
    { maxKeyframes: 16 } => 'scene.animations',
    { maxAnimationSeconds: 3 } => 'scene.animations[5]',
    { maxMorphTargets: 1 } => 'scene.meshes[0]',
    { maxSkins: 0 } => 'scene.skins',
    { maxJoints: 0 } => 'scene.skins[0].joints',
    { maxLights: 0 } => 'scene.extensions.KHR_lights_punctual.lights',
    { maxCameras: 0 } => 'scene.cameras',
    { glbMaxBytes: 100 } => 'scene',
    { jsonChunkMaxBytes: 100 } => 'scene'
  }.each do |over, path|
    test "counts: #{over.keys.first} → #{path}" do
      expect_error(G.fixture_glb, path, limits(over))
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
end
