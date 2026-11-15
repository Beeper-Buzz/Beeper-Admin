require 'test_helper'

# The glTF visualizer contract shared with the app and the web (spec §6.1): this repo's copies of
# the schema, the limits and the conformance fixtures must hash (after CRLF → LF) to the values in
# the workspace's specs/gltf-visualizer/SHA256SUMS. A change in one repo fails the others' tests
# until they copy it too. To update: copy the files from specs/gltf-visualizer and paste the new
# sums here.
class Beeper::GltfContractTest < ActiveSupport::TestCase
  SHA256SUMS = {
    'config/schemas/visualizer_gltf/visualizer-gltf.schema.json' =>
      'bb74f9b1be6d5815bee111a96251aabe4892d467acd8a24578efea75caf66dbd', # visualizer-gltf.schema.json
    'config/schemas/visualizer_gltf/visualizer-gltf.limits.json' =>
      '35c65107d8e5e9aa0752c74e675d35a7d4a4e415ca9ab1e9edbadaf5d44ece3c', # visualizer-gltf.limits.json
    'test/fixtures/files/visualizer_gltf/manifest-cases.json' =>
      '7436002510df77494285dea9d993edd761289e65b47e3f2b0996ca070d207481' # fixtures/manifest-cases.json
  }.freeze

  SHA256SUMS.each do |path, sum|
    test "#{File.basename(path)} matches specs/gltf-visualizer/SHA256SUMS" do
      text = File.binread(Rails.root.join(path)).gsub("\r\n", "\n")
      assert_equal sum, Digest::SHA256.hexdigest(text), "#{path} differs from the shared contract"
    end
  end

  test 'the limits are read from the JSON file once, frozen' do
    assert_equal JSON.parse(File.read(Beeper::Gltf::LIMITS_PATH)), Beeper::Gltf::LIMITS
    assert Beeper::Gltf::LIMITS.frozen?
    assert Beeper::Gltf::LIMITS['allowedExtensions'].frozen?
    assert Beeper::Gltf::LIMITS['outputBounds']['camera.dolly'].frozen?
    assert_equal 20 * 1024 * 1024, Beeper::Gltf::LIMITS['glbMaxBytes']
  end

  test 'the validator vocabulary matches the schema' do
    schema = JSON.parse(File.read(Beeper::Gltf::SCHEMA_PATH))
    text = JSON.generate(schema)
    v = Beeper::Manifests::VisualizerGltf
    (v::SOURCE_NAMES + v::DRUM_VOICES + v::CURVES + v::COMBINE_MODES + v::CLIP_MODES + v::NODE_PROPERTIES +
     v::MATERIAL_PROPERTIES + v::CAMERA_PROPERTIES + v::TARGET_KINDS).each do |word|
      assert_includes text, %("#{word}"), "#{word} is not in the schema"
    end
    assert_equal v::TOP_KEYS.sort, schema['properties'].keys.sort
  end
end
