require 'test_helper'

# Beeper's digital asset kinds (spec §1.5): sample_pack, effect_preset and visualizer manifests.
class Beeper::ManifestsTest < ActiveSupport::TestCase
  SHADER = <<~GLSL.freeze
    // Pulsing rings.
    float ring(vec2 p, float r) { return smoothstep(0.02, 0.0, abs(length(p) - r)); }

    vec4 beeperMain(vec2 uv) {
      vec2 p = uv - 0.5;
      float v = ring(p, 0.2 + uBass * 0.2) * (0.5 + uP_glow);
      return vec4(vec3(v), 1.0);
    }
  GLSL

  def asset_with(kind, files)
    asset = Spree::DigitalAsset.new(variant: create(:digital_product).master, kind: kind, manifest: {})
    asset.files.attach(files.map { |name, (bytes, type)| digital_blob(bytes, name, type || 'audio/wav') })
    asset
  end

  def sample_errors(manifest, files = %w[kick.wav snare.wav])
    Beeper::Manifests::SamplePack.call(manifest, asset_with('sample_pack', files.index_with { WAV_BYTES }))
  end

  def pack(samples = nil, **extra)
    { 'format' => 1, 'pack_id' => 'starter-kit',
      'samples' => samples || [{ 'file' => 'kick.wav', 'name' => 'Kick', 'pad' => 1 },
                               { 'file' => 'snare.wav', 'name' => 'Snare', 'root_note' => 62, 'pad' => 9 }] }.merge(extra)
  end

  def sample(**attrs)
    { 'file' => 'kick.wav', 'name' => 'Kick' }.merge(attrs.stringify_keys)
  end

  def assert_error(errors, text)
    assert errors.any? { |e| e.include?(text) }, "expected an error containing #{text.inspect}, got #{errors.inspect}"
  end

  WAV_BYTES = DigitalAssetsTestHelper::WAV_BYTES

  # --- sample_pack -------------------------------------------------------------------------------

  test 'sample_pack: a full valid manifest passes' do
    full = sample(root_note: 48, low_note: 36, high_note: 60, one_shot: false, gain_db: -3.5, start_ms: 0,
                  end_ms: 900, loop: { 'start_ms' => 100, 'end_ms' => 800 }, tags: %w[drum kick], pad: 16)
    assert_empty sample_errors(pack([full, sample(file: 'snare.wav', name: 'Snare')], 'bpm' => 120))
  end

  test 'sample_pack: pack_id and bpm are optional, symbol keys are read too' do
    assert_empty sample_errors({ format: 1, samples: [{ file: 'kick.wav', name: 'Kick' }] })
  end

  test 'sample_pack: format must be 1' do
    assert_error sample_errors(pack.merge('format' => 2)), 'format must be 1'
  end

  test 'sample_pack: pack_id invalid' do
    %w[ab Starter_Kit has\ space].each do |bad|
      assert_error sample_errors(pack.merge('pack_id' => bad)), 'pack_id invalid'
    end
    assert_error sample_errors(pack.merge('pack_id' => 'a' * 41)), 'pack_id invalid'
  end

  test 'sample_pack: bpm must be a positive number' do
    assert_error sample_errors(pack.merge('bpm' => 'fast')), 'bpm must be'
    assert_error sample_errors(pack.merge('bpm' => 0)), 'bpm must be'
  end

  test 'sample_pack: 1 to 64 samples' do
    assert_error sample_errors(pack([])), 'samples must be a list of 1 to 64'
    assert_error sample_errors(pack(nil).merge('samples' => 'kick.wav')), 'samples must be a list of 1 to 64'
    assert_error sample_errors(pack(Array.new(65) { sample })), 'samples must be a list of 1 to 64'
    assert_empty sample_errors(pack(Array.new(64) { sample }))
  end

  test 'sample_pack: file is required and must be attached' do
    assert_error sample_errors(pack([sample(file: nil)])), 'samples[0].file is required'
    assert_error sample_errors(pack([sample, sample(file: 'hat.wav')])), 'samples[1].file "hat.wav" is not attached'
  end

  test 'sample_pack: files must be wav, aiff, flac or mp3' do
    errors = Beeper::Manifests::SamplePack.call(
      pack([sample(file: 'kick.ogg')]), asset_with('sample_pack', 'kick.ogg' => [WAV_BYTES, 'audio/ogg'])
    )
    assert_error errors, 'samples[0].file "kick.ogg" must be wav, aiff, flac or mp3'
    %w[a.aif a.aiff a.flac a.mp3 a.WAV].each do |name|
      errors = Beeper::Manifests::SamplePack.call(pack([sample(file: name)]), asset_with('sample_pack', name => [WAV_BYTES]))
      assert_empty errors, name
    end
  end

  test 'sample_pack: without an asset the attachment check is skipped' do
    assert_empty Beeper::Manifests::SamplePack.call(pack([sample(file: 'elsewhere.wav')]))
  end

  test 'sample_pack: name is required' do
    assert_error sample_errors(pack([sample(name: ' ')])), 'samples[0].name is required'
  end

  test 'sample_pack: root_note must be 0..127' do
    errors = sample_errors(pack([sample, sample, sample, sample(root_note: 128)]))
    assert_error errors, 'samples[3].root_note must be 0..127'
    assert_error sample_errors(pack([sample(root_note: 60.5)])), 'samples[0].root_note must be 0..127'
    assert_error sample_errors(pack([sample(root_note: -1)])), 'samples[0].root_note must be 0..127'
  end

  test 'sample_pack: low_note and high_note come together, in range and in order' do
    errors = sample_errors(pack([sample, sample, sample, sample(low_note: 36)]))
    assert_error errors, 'samples[3].low_note given without high_note'
    assert_error sample_errors(pack([sample(high_note: 72)])), 'samples[0].high_note given without low_note'
    assert_error sample_errors(pack([sample(low_note: 0, high_note: 200)])), 'samples[0].high_note must be 0..127'
    assert_error sample_errors(pack([sample(low_note: 72, high_note: 60)])), 'samples[0].low_note must not be above high_note'
  end

  test 'sample_pack: pad must be 1..16 and used once' do
    assert_error sample_errors(pack([sample(pad: 0)])), 'samples[0].pad must be 1..16'
    assert_error sample_errors(pack([sample(pad: 17)])), 'samples[0].pad must be 1..16'
    assert_error sample_errors(pack([sample(pad: 3), sample(pad: 3)])), 'samples[1].pad 3 is already used by samples[0]'
  end

  test 'sample_pack: one_shot, gain_db, start/end, loop and tags' do
    assert_error sample_errors(pack([sample(one_shot: 'yes')])), 'samples[0].one_shot must be true or false'
    assert_error sample_errors(pack([sample(gain_db: 13)])), 'samples[0].gain_db must be -24..12'
    assert_error sample_errors(pack([sample(gain_db: -25)])), 'samples[0].gain_db must be -24..12'
    assert_error sample_errors(pack([sample(start_ms: -1)])), 'samples[0].start_ms must be a number of at least 0'
    assert_error sample_errors(pack([sample(start_ms: 500, end_ms: 400)])), 'samples[0].end_ms must be after start_ms'
    assert_error sample_errors(pack([sample(loop: { 'start_ms' => 10 })])), 'samples[0].loop needs start_ms and end_ms'
    assert_error sample_errors(pack([sample(loop: { 'start_ms' => 50, 'end_ms' => 50 })])), 'samples[0].loop end_ms must be after its start_ms'
    assert_error sample_errors(pack([sample(tags: ['ok', 3])])), 'samples[0].tags must be a list of strings'
  end

  # --- effect_preset -----------------------------------------------------------------------------

  def preset(effects)
    { 'format' => 1, 'effects' => effects }
  end

  def effect_errors(manifest)
    Beeper::Manifests::EffectPreset.call(manifest, nil)
  end

  test 'effect_preset: a valid preset passes' do
    manifest = preset([{ 'id' => 'reverb', 'enabled' => true, 'params' => { 'size' => 0.9, 'mix' => 0.4 } },
                       { 'id' => 'echo', 'enabled' => false, 'params' => { 'division' => 5, 'feedback' => 0.95 } },
                       { 'id' => 'compressor', 'enabled' => true, 'params' => { 'threshold' => -60, 'ratio' => 20 } }])
    assert_empty effect_errors(manifest)
  end

  test 'effect_preset: params may be left out' do
    assert_empty effect_errors(preset([{ 'id' => 'drive', 'enabled' => true }]))
  end

  test 'effect_preset: format must be 1' do
    assert_error effect_errors({ 'format' => '1', 'effects' => [{ 'id' => 'drive', 'enabled' => true }] }), 'format must be 1'
  end

  test 'effect_preset: effects must be a list of 1 to 9' do
    assert_error effect_errors(preset([])), 'effects must be a list of 1 to 9'
    assert_error effect_errors({ 'format' => 1 }), 'effects must be a list of 1 to 9'
  end

  test 'effect_preset: unknown and repeated ids' do
    assert_error effect_errors(preset([{ 'id' => 'flanger', 'enabled' => true }])), 'effects[0].id "flanger" unknown'
    errors = effect_errors(preset([{ 'id' => 'reverb', 'enabled' => true }, { 'id' => 'reverb', 'enabled' => false }]))
    assert_error errors, 'effects[1].id "reverb" repeated'
  end

  test 'effect_preset: enabled must be a boolean' do
    assert_error effect_errors(preset([{ 'id' => 'eq', 'enabled' => 1 }])), 'effects[0].enabled must be true or false'
  end

  test 'effect_preset: unknown params and values out of range' do
    assert_error effect_errors(preset([{ 'id' => 'reverb', 'enabled' => true, 'params' => { 'room' => 1 } }])),
                 'effects[0].params.room unknown for reverb'
    assert_error effect_errors(preset([{ 'id' => 'phaser', 'enabled' => true, 'params' => { 'feedback' => 0.95 } }])),
                 'effects[0].params.feedback must be a number in 0..0.9'
    assert_error effect_errors(preset([{ 'id' => 'eq', 'enabled' => true, 'params' => { 'midFreq' => 'high' } }])),
                 'effects[0].params.midFreq must be a number in 200..5000'
    assert_error effect_errors(preset([{ 'id' => 'eq', 'enabled' => true, 'params' => [] }])),
                 'effects[0].params must be an object'
  end

  # --- visualizer --------------------------------------------------------------------------------

  def viz(params = nil, shader: 'rings.glsl')
    { 'format' => 1, 'shader' => shader,
      'params' => params || [{ 'name' => 'glow', 'label' => 'Glow', 'min' => 0, 'max' => 1, 'default' => 0.5, 'drive' => 'bass' }] }
  end

  def viz_errors(manifest, source = SHADER, name: 'rings.glsl')
    asset = asset_with('visualizer', name => [source, 'text/plain'])
    Beeper::Manifests::Visualizer.call(manifest, asset)
  end

  test 'visualizer: a valid shader and params pass' do
    assert_empty viz_errors(viz)
    assert_empty viz_errors(viz([]))
  end

  test 'visualizer: format must be 1' do
    assert_error viz_errors(viz.merge('format' => 0)), 'format must be 1'
  end

  test 'visualizer: shader must name an attached .glsl file' do
    assert_error viz_errors(viz(shader: nil)), 'shader must name a .glsl file'
    assert_error viz_errors(viz(shader: 'rings.txt')), 'shader must name a .glsl file'
    assert_error viz_errors(viz(shader: 'other.glsl')), 'shader "other.glsl" is not attached'
  end

  test 'visualizer: shader must define beeperMain' do
    assert_error viz_errors(viz, "vec4 notMain(vec2 uv) { return vec4(1.0); }\n"), 'shader must define beeperMain'
    commented = "// vec4 beeperMain(vec2 uv) { }\nvec4 other(vec2 uv) { return vec4(1.0); }\n"
    assert_error viz_errors(viz, commented), 'shader must define beeperMain'
  end

  test 'visualizer: shader too large' do
    big = SHADER + ("// #{'x' * 1000}\n" * 66)
    assert_operator big.bytesize, :>, 64.kilobytes
    assert_error viz_errors(viz, big), 'shader too large'
  end

  test 'visualizer: forbidden declarations' do
    {
      "uniform float uExtra;\n" => 'uniform declarations not allowed',
      "attribute vec2 aPos;\n" => 'attribute declarations not allowed',
      "varying vec2 vUv;\n" => 'varying declarations not allowed',
      "precision highp float;\n" => 'precision statements not allowed',
      "#version 300 es\n" => '#version not allowed',
      "#extension GL_OES_standard_derivatives : enable\n" => '#extension not allowed',
      "#include \"noise.glsl\"\n" => '#include not allowed',
      "void main() { gl_FragColor = beeperMain(vec2(0.0)); }\n" => 'void main not allowed'
    }.each do |line, message|
      assert_error viz_errors(viz, SHADER + line), message
    end
  end

  test 'visualizer: forbidden words inside comments are fine' do
    assert_empty viz_errors(viz, "/* no uniform here, and no precision */\n// void main() lives in the host\n#{SHADER}")
  end

  test 'visualizer: params rules' do
    nine = Array.new(9) { |i| { 'name' => "p#{i}", 'label' => "P#{i}", 'min' => 0, 'max' => 1, 'default' => 0 } }
    assert_error viz_errors(viz(nine)), 'params must be a list of at most 8'
    good = { 'name' => 'glow', 'label' => 'Glow', 'min' => 0, 'max' => 1, 'default' => 0.5 }
    bad = [good, good.merge('name' => 'speed'), good.merge('name' => 'Bad-Name')]
    assert_error viz_errors(viz(bad)), 'params[2].name invalid'
    assert_error viz_errors(viz([good, good])), 'params[1].name "glow" repeated'
    assert_error viz_errors(viz([good.merge('name' => 'a' * 25)])), 'params[0].name invalid'
    assert_error viz_errors(viz([good.merge('label' => '')])), 'params[0].label is required'
    assert_error viz_errors(viz([good.merge('min' => 'zero')])), 'params[0].min must be a number'
    assert_error viz_errors(viz([good.merge('min' => 1, 'max' => 0)])), 'params[0] needs min < max'
    assert_error viz_errors(viz([good.merge('default' => 2)])), 'params[0].default must be within min..max'
    assert_error viz_errors(viz([good.merge('drive' => 'treble')])), 'params[0].drive must be one of bass, mid, high, level, beat'
  end

  # --- wiring ------------------------------------------------------------------------------------

  test 'apply sets the three kinds and their validators on a DigitalAssets config' do
    config = DigitalAssets::Config.new
    Beeper::DigitalKinds.apply(config)
    assert_equal %w[sample_pack effect_preset visualizer], config.kinds
    assert_equal config.kinds.sort, config.manifest_validators.keys.sort
  end

  test 'the kinds are installed everywhere but the test environment' do
    assert Beeper::DigitalKinds.install?(ActiveSupport::StringInquirer.new('production'))
    assert Beeper::DigitalKinds.install?(ActiveSupport::StringInquirer.new('development'))
    refute Beeper::DigitalKinds.install?(ActiveSupport::StringInquirer.new('test'))
  end

  test 'with the kinds installed, an asset of another kind is invalid and manifest errors land on the asset' do
    with_beeper_kinds do
      other = Spree::DigitalAsset.new(variant: create(:digital_product).master, kind: 'pack', manifest: {})
      refute other.valid?
      assert other.errors[:kind].any?

      asset = asset_with('sample_pack', 'kick.wav' => [WAV_BYTES])
      asset.manifest = pack([sample(root_note: 300)])
      refute asset.valid?
      assert asset.errors[:manifest].any? { |e| e.include?('samples[0].root_note must be 0..127') }
    end
  end

  test 'with the kinds installed, a draft may keep an empty manifest but cannot be published with it' do
    with_beeper_kinds do
      asset = asset_with('sample_pack', 'kick.wav' => [WAV_BYTES])
      assert asset.valid?, asset.errors.full_messages.inspect
      asset.save!
      assert_raises(ActiveRecord::RecordInvalid) { asset.publish! }

      asset.reload.update!(manifest: pack([sample]))
      assert asset.publish!.published?
    end
  end
end
