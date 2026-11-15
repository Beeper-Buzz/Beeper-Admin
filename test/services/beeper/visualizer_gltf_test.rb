require 'test_helper'

# Beeper::Manifests::VisualizerGltf: the Ruby port of the shared core's manifest validator, plus the
# server's file checks. The structural and semantic cases mirror
# specs/gltf-visualizer/ts/__tests__/manifest.test.ts; every case of manifest-cases.json runs.
class Beeper::VisualizerGltfTest < ActiveSupport::TestCase
  G = GltfTestGlb
  V = Beeper::Manifests::VisualizerGltf

  setup { Beeper::Gltf::InspectionCache.clear! }

  def cases
    G.manifest_cases
  end

  def summary
    cases['summary']
  end

  def validate(manifest, sum = nil, **opts)
    V.validate(manifest, sum, **opts)
  end

  def path_of(error)
    i = error.index(': ')
    i ? error[0...i] : error
  end

  def paths(errors)
    errors.map { |e| path_of(e) }
  end

  def path_matches?(error, expected)
    path = path_of(error)
    path == expected || path.start_with?("#{expected}.") || path.start_with?("#{expected}[")
  end

  def base(audio = {}, extra = {})
    { 'format' => 1, 'type' => 'gltf', 'scene' => 's.glb', 'audio' => { 'schemaVersion' => 1 }.merge(audio.deep_stringify_keys) }
      .merge(extra.deep_stringify_keys)
  end

  # --- fixtures/manifest-cases.json --------------------------------------------------------------

  test 'fixtures: 4 valid and 50 invalid cases' do
    assert_equal 4, cases['valid'].size
    assert_equal 50, cases['invalid'].size
  end

  test 'fixtures: every valid case gives no errors, with and without the summary' do
    cases['valid'].each do |c|
      assert_equal [], validate(c['manifest'], summary), c['name']
      assert_equal [], validate(c['manifest'], nil), c['name']
    end
  end

  test 'fixtures: every invalid case gives an error at its path, in "<path>: <message>" form' do
    cases['invalid'].each do |c|
      errors = validate(c['manifest'], summary)
      assert errors.any?, "#{c['name']}: expected errors"
      assert errors.any? { |e| path_matches?(e, c['errorPath']) }, "#{c['name']}: no error at #{c['errorPath']}; got:\n  #{errors.join("\n  ")}"
      errors.each { |e| assert_match(/\A[^:]+: \S/, e, "#{c['name']}: \"<path>: <message>\" form") }
    end
  end

  test 'fixtures: schema-only cases fail without a summary too; name cases need it' do
    cases['invalid'].select { |c| c['schemaOnly'] }.each do |c|
      assert validate(c['manifest'], nil).any?, c['name']
    end
    name_case = cases['invalid'].find { |c| c['name'] == 'unknown node' }
    assert_equal [], validate(name_case['manifest'], nil)
  end

  test 'fixtures: .call without an asset agrees with validate (no files, no names)' do
    (cases['valid'] + cases['invalid']).each do |c|
      assert_equal validate(c['manifest'], nil), V.call(c['manifest']), c['name']
    end
  end

  # --- structure ---------------------------------------------------------------------------------

  test 'not an object' do
    assert_equal ['manifest: must be an object'], validate(nil, nil)
    assert_equal ['manifest: must be an object'], validate([], nil)
    assert_equal ['manifest: must be an object'], V.call('x')
  end

  test 'unknown keys at depth are reported at their own path' do
    m = base({ bindings: [{ source: 'bass', smoothing: { attackMs: 1, holdMs: 3 }, target: { kind: 'node', node: 'Cone', property: 'scale' } }] },
             { view: { camera: { zoom: 2 } }, materials: [{ material: 'Skin', toon: { steps: 2, outline: { width: 0.01, blur: 1 } } }] })
    assert_equal ['audio.bindings[0].smoothing.holdMs', 'materials[0].toon.outline.blur', 'view.camera.zoom'], paths(validate(m, nil)).sort
    assert_includes validate(m, nil), 'view.camera.zoom: unknown key'
  end

  test 'symbol keys are read like string keys' do
    assert_equal [], V.call({ format: 1, type: 'gltf', scene: 's.glb', audio: { schemaVersion: 1 } })
  end

  test 'names are 1..128 code points; ids follow the pattern' do
    long = 'x' * 129
    emoji = '😀' * 128 # 256 UTF-16 units, 128 code points
    m = ->(node, id) { base({ bindings: [{ id: id, source: 'bass', target: { kind: 'node', node: node, property: 'scale' } }] }) }
    assert_equal [], validate(m.call(emoji, 'ok_1'), nil)
    assert_equal ['audio.bindings[0].id', 'audio.bindings[0].target.node'], paths(validate(m.call(long, 'bad id'), nil)).sort
  end

  test 'integers, enums, ranges and colours' do
    m = base({ idle: { clips: [{ clip: 'Fan', timeScale: 5 }] },
               noteClips: { initial: 'Idle', priority: 'loudest', rules: [{ match: { part: 'keys', note: 60.5 }, clip: 'Dance1', sync: 'half' }] },
               bindings: [{ sources: [{ source: 'bass', weight: 9 }], curve: 'bounce', inputRange: [0],
                            target: { kind: 'material', material: 'Neon', property: 'color', colors: ['#fff', '#000000'] } }] },
             { view: { exposure: 9, lighting: 'disco' } })
    assert_equal %w[audio.bindings[0].curve audio.bindings[0].inputRange audio.bindings[0].sources[0].weight
                    audio.bindings[0].target.colors[0] audio.idle.clips[0].timeScale audio.noteClips.priority
                    audio.noteClips.rules[0].match.note audio.noteClips.rules[0].sync view.exposure view.lighting],
                 paths(validate(m, nil)).sort
  end

  test 'whole floats count as integers, as in JSON' do
    m = base({ noteClips: { initial: 'Idle', rules: [{ match: { part: 'keys', note: 60.0 }, clip: 'Dance1' }] } },
             { format: 1.0, materials: [{ material: 'Skin', toon: { steps: 3.0 } }] })
    assert_equal [], validate(m, nil)
  end

  test 'limits drive the list sizes' do
    bindings = Array.new(3) { { source: 'bass', target: { kind: 'node', node: 'Cone', property: 'scale' } } }
    assert_equal [], validate(base({ bindings: bindings }), nil)
    errors = validate(base({ bindings: bindings }), nil, limits: Beeper::Gltf::LIMITS.merge('maxBindings' => 2))
    assert_equal ['audio.bindings'], paths(errors)
  end

  test 'messages name the field and print numbers as JavaScript does' do
    assert_includes validate(base({}, { view: { exposure: 9 } }), nil), 'view.exposure: must be between 0.25 and 4'
    assert_includes validate(base({}, { type: 'shader' }), nil), 'type: must be "gltf"'
    assert_includes validate(base({}, { scene: 's.gltf' }), nil), 'scene: must be a .glb file name without a directory'
  end

  # --- semantic rules ----------------------------------------------------------------------------

  test 'node targets add up; other targets are unique' do
    node = { kind: 'node', node: 'Cone', property: 'position' }
    assert_equal [], validate(base({ bindings: [{ source: 'bass', target: node }, { source: 'kick', target: node }] }), summary)
    cam = { kind: 'camera', property: 'dolly' }
    errors = validate(base({ bindings: [{ source: 'bass', target: cam }, { source: 'kick', target: cam }] }), summary)
    assert_equal ['audio.bindings[1].target'], paths(errors)
  end

  test 'speed + weight combine on one clip; play and trigger stand alone' do
    t = ->(mode) { { source: 'bass', target: { kind: 'clip', clip: 'Fan', mode: mode } } }
    assert_equal [], validate(base({ bindings: [t.call('speed'), t.call('weight')] }), summary)
    assert_equal ['audio.bindings[1].target.mode'], paths(validate(base({ bindings: [t.call('play'), t.call('trigger')] }), summary))
    assert_equal ['audio.bindings[1].target'], paths(validate(base({ bindings: [t.call('speed'), t.call('speed')] }), summary))
  end

  test 'a clip owned by idle cannot be bound; a rule may reuse the initial clip' do
    errors = validate(base({ idle: { clips: [{ clip: 'Fan' }] }, bindings: [{ source: 'bass', target: { kind: 'clip', clip: 'Fan', mode: 'weight' } }] }), summary)
    assert_equal ['audio.bindings[0].target.clip'], paths(errors)
    ok = base({ noteClips: { initial: 'Idle', rules: [{ match: { part: 'drums', voice: 'kick' }, clip: 'Idle', mode: 'once' }] } })
    assert_equal [], validate(ok, summary)
  end

  test 'outputRange: within bounds, reversed allowed; morph index and threshold bounds' do
    b = ->(range) { base({ bindings: [{ source: 'bass', outputRange: range, target: { kind: 'camera', property: 'dolly' } }] }) }
    assert_equal [], validate(b.call([5, 0.2]), nil)
    assert_equal ['audio.bindings[0].outputRange'], paths(validate(b.call([0.1, 1]), nil))
    m = base({ bindings: [{ source: 'bass', target: { kind: 'morph', mesh: 'Body', morph: 32 } },
                          { source: 'kick', target: { kind: 'clip', clip: 'Pump', mode: 'trigger', threshold: 0 } }] })
    assert_equal ['audio.bindings[0].target.morph', 'audio.bindings[1].target.threshold'], paths(validate(m, nil))
  end

  test 'slots range lo ≤ hi; drum voices unique' do
    m = base({ noteClips: { initial: 'Idle', rules: [{ match: { part: 'sampler', slots: [9, 3] }, clip: 'Wave' },
                                                     { match: { part: 'drums', voices: %w[kick kick] }, clip: 'Pump' }] } })
    assert_equal ['audio.noteClips.rules[0].match.slots', 'audio.noteClips.rules[1].match.voices[1]'], paths(validate(m, nil))
  end

  test 'names: ambiguous morph, unknown light node, camera on a light node' do
    sum = summary.merge('meshes' => [{ 'name' => 'Body', 'morphs' => %w[Smile Smile] }])
    m = base({ bindings: [{ source: 'bass', target: { kind: 'morph', mesh: 'Body', morph: 'Smile' } },
                          { source: 'mid', target: { kind: 'light', light: 'Nope', property: 'intensity' } }] },
             { view: { camera: { node: 'KeyLight' } } })
    assert_equal ['view.camera.node', 'audio.bindings[1].target.light', 'audio.bindings[0].target.morph'], paths(validate(m, sum))
  end

  test 'outlines count toward maxDrawCalls when stats are given' do
    stats = { 'drawCalls' => 100, 'materialDrawCalls' => [20, 5, 10, 0, 0] }
    outlined = ->(materials) { validate(base.merge('materials' => materials.map(&:deep_stringify_keys)), summary, stats: stats) }
    assert_equal [], outlined.call([{ material: 'Outfit', toon: { steps: 2, outline: { width: 0.01 } } }]) # 105
    assert_equal ['materials'], paths(outlined.call([{ material: 'Skin', toon: { steps: 2, outline: { width: 0.01 } } },
                                                     { material: 'Neon', toon: { steps: 2, outline: { width: 0.01 } } }])) # 130
    # "*" outlines everything not named; a named override without outline opts out.
    assert_equal [], outlined.call([{ material: '*', toon: { steps: 2, outline: { width: 0.01 } } }, { material: 'Skin', toon: { steps: 2 } }]) # 115
    assert_equal ['materials'], paths(outlined.call([{ material: '*', toon: { steps: 2, outline: { width: 0.01 } } }])) # 135
    # Without stats the check is skipped.
    assert_equal [], validate(base.merge('materials' => [{ 'material' => '*', 'toon' => { 'steps' => 2, 'outline' => { 'width' => 0.01 } } }]), summary)
    assert_equal 135, V.draw_calls(base.merge('materials' => [{ 'material' => '*', 'toon' => { 'steps' => 2, 'outline' => { 'width' => 0.01 } } }]), summary, stats)
  end

  # --- files (an asset with attached blobs) ------------------------------------------------------

  def dancer
    cases['valid'].find { |c| c['name'] == 'dancer example' }['manifest']
  end

  def gltf_asset(files)
    asset = Spree::DigitalAsset.new(variant: create(:digital_product).master, kind: 'visualizer', manifest: {})
    asset.files.attach(files.map { |name, (bytes, type)| digital_blob(bytes, name, type) }) if files.any?
    asset
  end

  def dancer_files(**over)
    { 'dancer.glb' => [G.fixture_glb, 'model/gltf-binary'], 'poster.jpg' => [G.jpeg_header(640, 360), 'image/jpeg'] }.merge(over)
  end

  # Counts ActiveStorage::Blob#download calls while the block runs.
  def downloads
    count = 0
    counter = ->(*) { count += 1 }
    ActiveSupport::Notifications.subscribed(counter, 'service_download.active_storage') { yield }
    count
  end

  test 'files: the dancer with its GLB and poster attached is valid' do
    assert_equal [], V.call(dancer, gltf_asset(dancer_files))
  end

  test 'files: the scene and the poster must be attached' do
    errors = V.call(dancer, gltf_asset('other.glb' => [G.fixture_glb, 'model/gltf-binary']))
    assert_includes errors, 'scene: "dancer.glb" is not attached'
    assert_includes errors, 'poster: "poster.jpg" is not attached'
    assert(errors.any? { |e| e.start_with?('files: "other.glb" is not named by the manifest') }, errors.inspect)
  end

  test 'files: no file the manifest does not name' do
    errors = V.call(dancer, gltf_asset(dancer_files('notes.json' => ['{}', 'application/json'])))
    assert_equal ['files'], paths(errors)
  end

  test 'files: a poster over 2 MB or not an image is refused without a download' do
    asset = gltf_asset(dancer_files)
    poster = asset.files.attachments.map(&:blob).find { |b| b.filename.to_s == 'poster.jpg' }
    poster.byte_size = 2.megabytes + 1
    assert_equal ['poster: the file is 2.0 MB; the limit is 2.0 MB'], V.call(dancer, asset)

    asset = gltf_asset(dancer_files)
    poster = asset.files.attachments.map(&:blob).find { |b| b.filename.to_s == 'poster.jpg' }
    poster.content_type = 'application/octet-stream'
    assert_equal ['poster: must be a PNG, JPEG or WebP image (the upload is application/octet-stream)'], V.call(dancer, asset)
  end

  test 'files: a scene over 20 MB is refused by its byte size, before any download' do
    asset = gltf_asset(dancer_files)
    scene = asset.files.attachments.map(&:blob).find { |b| b.filename.to_s == 'dancer.glb' }
    scene.byte_size = 20.megabytes + 1
    errors = nil
    assert_equal 0, downloads { errors = V.call(dancer, asset) }
    assert_equal ['scene: the file is 20.0 MB; the limit is 20.0 MB'], errors.reject { |e| e.start_with?('audio', 'view', 'materials') }
  end

  test 'files: GLB errors and name errors come from the downloaded scene' do
    broken = G.build(G.fixture_scene.merge(extensions_used: ['KHR_draco_mesh_compression']))
    errors = V.call(dancer, gltf_asset(dancer_files('dancer.glb' => [broken, 'model/gltf-binary'])))
    assert_equal ['scene.extensionsUsed: KHR_draco_mesh_compression: ' + Beeper::Gltf::LIMITS['rejectedExtensions']['KHR_draco_mesh_compression']], errors

    tiny = G.build(nodes: [{ name: 'A', mesh: 0 }], meshes: [{ name: 'M', primitives: [G.cube(1, 0)] }], materials: [{ name: 'Mat' }])
    errors = V.call(dancer, gltf_asset(dancer_files('dancer.glb' => [tiny, 'model/gltf-binary'])))
    assert_includes errors, 'audio.bindings[0].target.node: "Cone" is not a node in the scene'
    assert_includes errors, 'audio.noteClips.initial: "Idle" is not an animation in the scene'
  end

  test 'files: a file that is not a GLB stops at the header, and names are not resolved' do
    errors = V.call(dancer, gltf_asset(dancer_files('dancer.glb' => ['not a glb at all, really', 'model/gltf-binary'])))
    assert_equal ['scene: not a GLB file (no glTF magic); export glTF Binary (.glb)'], errors
  end

  test 'files: outlines count toward the draw calls of the attached scene' do
    m = dancer.deep_dup
    m['materials'] = [{ 'material' => '*', 'toon' => { 'steps' => 2, 'outline' => { 'width' => 0.01 } } }]
    four = G.fixture_scene.merge(nodes: G.fixture_scene[:nodes] + Array.new(60) { |i| { name: "Speaker#{i}", mesh: 1 } })
    four[:nodes][0] = four[:nodes][0].merge(children: [1, 3, 5, 6, 7, 8] + (9...69).to_a)
    # 4 + 60 = 64 draw calls; the outlines double them to 128: at the limit.
    assert_equal [], V.call(m, gltf_asset(dancer_files('dancer.glb' => [G.build(four), 'model/gltf-binary'])))
    five = four.merge(nodes: four[:nodes] + [{ name: 'One more', mesh: 1 }])
    errors = V.call(m, gltf_asset(dancer_files('dancer.glb' => [G.build(five), 'model/gltf-binary'])))
    assert_equal ['materials: outlines raise the draw calls to 130; the limit is 128'], errors
  end

  test 'files: inspections are memoised per blob (an LRU of 4)' do
    asset = gltf_asset(dancer_files)
    assert_equal 1, downloads { V.call(dancer, asset) }
    assert_equal 0, downloads { 3.times { V.call(dancer, asset) } }

    scenes = Array.new(4) { |i| G.build(G.fixture_scene.merge(materials: G.fixture_scene[:materials] + [{ name: "Extra#{i}" }])) }
    assert_equal 4, downloads { scenes.each { |bytes| V.call(dancer, gltf_asset(dancer_files('dancer.glb' => [bytes, 'model/gltf-binary']))) } }
    assert_equal 4, Beeper::Gltf::InspectionCache.size
    assert_equal 1, downloads { V.call(dancer, asset) } # the first scene was evicted
  end

  test 'files: the memo is keyed by the blob, not its checksum (a colliding MD5 cannot reuse a clean result)' do
    clean = gltf_asset(dancer_files)
    assert_equal [], V.call(dancer, clean)
    clean_scene = clean.files.attachments.map(&:blob).find { |b| b.filename.to_s == 'dancer.glb' }

    broken = G.build(G.fixture_scene.merge(extensions_used: ['KHR_draco_mesh_compression']))
    other = gltf_asset(dancer_files('dancer.glb' => [broken, 'model/gltf-binary']))
    other_scene = other.files.attachments.map(&:blob).find { |b| b.filename.to_s == 'dancer.glb' }
    other_scene.checksum = clean_scene.checksum # as if the MD5s collided
    errors = nil
    assert_equal 1, downloads { errors = V.call(dancer, other) }
    assert(errors.any? { |e| e.include?('KHR_draco_mesh_compression') }, errors.inspect)
  end

  test 'files: inspections that hit a work cap are not memoised' do
    crafted = G.build(G.fixture_scene.merge(edit_json: ->(j) { j['bufferViews'] += Array.new(150) { {} } }))
    asset = gltf_asset(dancer_files('dancer.glb' => [crafted, 'model/gltf-binary']))
    errors = nil
    assert_equal 1, downloads { errors = V.call(dancer, asset) }
    assert_equal 'scene: …and 50 more problems', errors.last
    assert_equal 0, Beeper::Gltf::InspectionCache.size
    assert_equal 1, downloads { V.call(dancer, asset) }
  end

  test 'files: a scene that cannot be downloaded is an error, not an exception' do
    asset = gltf_asset(dancer_files)
    scene = asset.files.attachments.map(&:blob).find { |b| b.filename.to_s == 'dancer.glb' }
    scene.service.delete(scene.key)
    assert_equal ['scene: "dancer.glb" could not be read'], V.call(dancer, asset)
  end

  # --- BindingsSummary on malformed drafts --------------------------------------------------------

  test 'the bindings summary never raises on a malformed draft (idle as a string or an array, odd shapes)' do
    summary = Beeper::Gltf::BindingsSummary
    ['Fan', ['Fan'], 7, nil].each do |idle|
      sections = summary.call(dancer.deep_merge('audio' => { 'idle' => idle }))
      refute_includes sections.map(&:first), 'Idle', idle.inspect
      assert_includes sections.map(&:first), 'Bindings'
    end
    assert_equal [['Idle', ['(unreadable)']]], summary.call('audio' => { 'idle' => { 'clips' => ['Fan'] } }).reject { |t, _| t == 'View' }
    odd = { 'audio' => 'x', 'materials' => 'x', 'view' => [] }
    assert_equal ['View'], summary.call(odd).map(&:first)
    assert_equal ['View'], summary.call('audio' => { 'bindings' => 'x', 'noteClips' => [], 'idle' => [] }).map(&:first)
    assert_equal ['Bindings', ['(unreadable)']], summary.call('audio' => { 'bindings' => [7] }).first
  end

  # --- dispatch (Beeper::Manifests::Visualizer) ---------------------------------------------------

  test 'dispatch: type gltf goes to the glTF validator; shader or no type to the shader one; others are refused' do
    assert_equal [], Beeper::Manifests::Visualizer.call(dancer, gltf_asset(dancer_files))
    assert_equal ['scene: "dancer.glb" is not attached', 'poster: "poster.jpg" is not attached'],
                 Beeper::Manifests::Visualizer.call(dancer, gltf_asset({}))
    assert_equal ['type: must be shader or gltf'], Beeper::Manifests::Visualizer.call({ 'format' => 1, 'type' => 'video' })
    assert_equal ['type: must be shader or gltf'], Beeper::Manifests::Visualizer.call({ 'format' => 1, 'type' => nil })
    shader = { 'format' => 1, 'shader' => 'rings.glsl', 'params' => [] }
    assert_equal [], Beeper::Manifests::Visualizer.call(shader)
    assert_equal [], Beeper::Manifests::Visualizer.call(shader.merge('type' => 'shader'))
    assert_equal ['shader must name a .glsl file'], Beeper::Manifests::Visualizer.call(dancer.merge('type' => 'shader'))
  end

  test 'with the kinds installed, a glTF visualizer saves, publishes and lands its errors on the asset' do
    with_beeper_kinds do
      asset = gltf_asset(dancer_files)
      asset.manifest = dancer
      asset.save!
      assert asset.publish!.published?

      draft = gltf_asset(dancer_files)
      draft.manifest = dancer.merge('scene' => 'missing.glb')
      refute draft.valid?
      assert draft.errors[:manifest].any? { |e| e.include?('scene: "missing.glb" is not attached') }, draft.errors.full_messages.inspect
    end
  end

  # --- uploads -----------------------------------------------------------------------------------

  test 'uploads: .glb scenes up to 20 MB as model/gltf-binary or application/octet-stream' do
    config = Beeper::Marketplace.apply_uploads(Uploads::Config.new)
    assert_equal 20.megabytes, config.rule_for('dancer.glb', 'model/gltf-binary')[:max_bytes]
    assert_equal 20.megabytes, config.rule_for('Dancer.GLB', 'application/octet-stream')[:max_bytes]
    assert_nil config.rule_for('dancer.gltf', 'model/gltf+json')
    assert_nil config.rule_for('dancer.glb', 'image/png')
    assert_nil config.rule_for('dancer.bin', 'application/octet-stream')
    # The poster is an image under the generic rule; the shader rule is unchanged.
    assert config.rule_for('poster.webp', 'image/webp')
    assert_equal 64.kilobytes, config.rule_for('rings.glsl', 'application/octet-stream')[:max_bytes]
  end
end
