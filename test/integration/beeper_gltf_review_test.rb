require 'test_helper'

# Beeper's glTF visualizer screens in the admin: the creator review page and the digital asset page
# show the 3D preview (model-viewer over the same-origin Active Storage proxy), the poster, the
# bindings in words and the GLB stats for a glTF draft, and nothing new for a shader draft. The
# decision flow stays the existing one.
class BeeperGltfReviewTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  G = GltfTestGlb

  setup do
    Beeper::Gltf::InspectionCache.clear!
    digital_store
    @admin = admin_user
    @creator = creator_user
  end

  teardown { Warden.test_reset! }

  def dancer
    G.manifest_cases['valid'].find { |c| c['name'] == 'dancer example' }['manifest']
  end

  # A submitted creator product whose draft is the dancer: dancer.glb and poster.jpg attached
  # (files first, then the manifest, as the creator portal does, so it validates with the kinds on).
  def gltf_product(manifest = dancer)
    product = creator_product(@creator, kind: 'visualizer', manifest: {}, files: {})
    asset = Spree::DigitalAsset.draft.find_by!(variant_id: product.master.id)
    asset.attach_files!([digital_blob(G.fixture_glb, 'dancer.glb', 'model/gltf-binary'),
                         digital_blob(G.jpeg_header(640, 360), 'poster.jpg', 'image/jpeg')])
    asset.update!(manifest: manifest)
    product.update!(review_state: 'submitted', submitted_at: Time.current)
    product
  end

  def shader_product
    product = creator_product(@creator, kind: 'visualizer',
                                        manifest: { 'format' => 1, 'shader' => 'rings.glsl', 'params' => [] },
                                        files: { 'rings.glsl' => "vec4 beeperMain(vec2 uv) { return vec4(1.0); }\n" })
    product.update!(review_state: 'submitted', submitted_at: Time.current)
    product
  end

  test 'the review page of a glTF draft shows the 3D preview, poster, bindings and stats' do
    product = gltf_product
    login_as(@admin, scope: :spree_user)
    get "/admin/creator_reviews/#{product.id}"
    assert_response :success
    body = response.body

    # After the Product card, before the existing Preview card.
    preview_at = body.index('id="beeper_gltf_preview"')
    assert preview_at, 'no glTF preview'
    assert_operator body.index('>Product</h1>'), :<, preview_at
    assert_operator preview_at, :<, body.index('>Preview</h2>')

    # model-viewer, pinned with SRI, loading the GLB and the poster through the proxy route.
    assert_includes body, %(<script type="module" src="#{Beeper::Gltf::MODEL_VIEWER_URL}" integrity="#{Beeper::Gltf::MODEL_VIEWER_INTEGRITY}" crossorigin="anonymous">)
    assert_match %r{<model-viewer id="beeper_gltf_viewer"\s+src="/rails/active_storage/blobs/proxy/[^"]+/dancer\.glb"}, body
    assert_match %r{poster="/rails/active_storage/blobs/proxy/[^"]+/poster\.jpg"}, body
    assert_includes body, 'camera-controls autoplay'
    assert_includes body, 'background-color: #07040F'

    # Bindings, note → clip rules, idle, materials and view in words.
    [
      'kick → Cone.scale xyz 1 → 1.25, easeOut, attack 0 ms, release 140 ms (kick-thump)',
      'max(0.7×bass, 0.5×hit) → Neon.emissiveIntensity 0.5 → 6, exp, attack 10 ms, release 300 ms (bass-glow)',
      'notePulse → Body morph Smile 0 → 1, linear (smile)',
      'hats → Body morph #1 0 → 1, step × 2 (blink)',
      'barPhase → Hips.rotation z -6 → 6, easeInOut (hip-sway)',
      'start in Idle, fade 250 ms, priority velocity, on stop initial, back to Idle after 8000 ms of silence',
      'keys notes 48–59 → Dance1 loop, sync beat, tempo-synced to 120 BPM',
      'sampler pad 16 → Wave once, fade 120 ms',
      'drums clap, rim → Pump once, velocity → weight 0.5..1',
      'Fan ×0.5',
      'Skin: 3 steps, outline 0.006 #120A1E',
      '* (every other material): 2 steps'
    ].each { |line| assert_includes CGI.unescapeHTML(body), line }

    # GLB stats from the inspection, outlines included in the draw calls.
    stats = CGI.unescapeHTML(body[body.index('id="beeper_gltf_stats"')..])
    assert_includes stats, '37 of 300,000'
    assert_includes stats, '27 of 400,000'
    assert_includes stats, '5 of 128 (4 + 1 outline)' # only Skin is outlined: one primitive, one instance
    assert_includes stats, 'Dance1: 1.92 s, 3 keyframes'
    assert_includes stats, '9 nodes, 2 meshes, 5 materials, 2 morph targets, 1 skin, 1 light, 1 camera'

    # The existing page is still there: files, manifest, decision forms.
    assert_includes body, 'dancer.glb'
    assert_includes body, '&quot;type&quot;: &quot;gltf&quot;'
    assert_includes body, 'id="approve_creator_product"'
  end

  # The proxy route is a public signed URL, not admin-only: the same exposure as the existing
  # rails_blob_path links to a draft's files on this page. It only keeps model-viewer same-origin.
  test 'the proxy URL serves the GLB from this origin' do
    product = gltf_product
    login_as(@admin, scope: :spree_user)
    get "/admin/creator_reviews/#{product.id}"
    src = response.body[%r{src="(/rails/active_storage/blobs/proxy/[^"]+/dancer\.glb)"}, 1]
    assert src
    get src
    assert_response :success
    assert_equal G.fixture_glb, response.body.b
  end

  test 'the review page of a shader draft is unchanged' do
    product = shader_product
    login_as(@admin, scope: :spree_user)
    get "/admin/creator_reviews/#{product.id}"
    assert_response :success
    refute_includes response.body, 'beeper_gltf_preview'
    refute_includes response.body, 'model-viewer'
    assert_includes response.body, 'rings.glsl'
    assert_includes response.body, '&quot;shader&quot;'
  end

  test 'a scene with GLB errors shows them' do
    product = gltf_product
    asset = Spree::DigitalAsset.draft.find_by!(variant_id: product.master.id)
    asset.files.attachments.find { |a| a.filename.to_s == 'dancer.glb' }.purge
    asset.reload.attach_files!([digital_blob(G.build(G.fixture_scene.merge(extensions_used: ['EXT_meshopt_compression'])), 'dancer.glb', 'model/gltf-binary')])
    login_as(@admin, scope: :spree_user)
    get "/admin/creator_reviews/#{product.id}"
    assert_response :success
    assert_includes CGI.unescapeHTML(response.body), "scene.extensionsUsed: EXT_meshopt_compression: meshopt needs a WebAssembly decoder the app can't run"
  end

  test 'approve, request changes and reject stay the existing flow for a glTF draft' do
    with_beeper_kinds do
      product = gltf_product
      login_as(@admin, scope: :spree_user)
      post "/admin/creator_reviews/#{product.id}/approve", params: { review_note: 'Great dancer' }
      assert_redirected_to '/admin/creator_reviews'
      assert_equal 'approved', product.reload.review_state
      assert_equal 'gltf', product.master.live_digital_asset.manifest['type']

      second = gltf_product
      post "/admin/creator_reviews/#{second.id}/request_changes", params: { review_note: 'Brighter neon' }
      assert_equal 'changes_requested', second.reload.review_state
    end
  end

  test 'the digital asset page of a glTF visualizer shows the preview; a shader one does not' do
    product = gltf_product
    asset = Spree::DigitalAsset.draft.find_by!(variant_id: product.master.id)
    login_as(@admin, scope: :spree_user)
    get "/admin/products/#{product.slug}/digital_assets/#{asset.id}/edit"
    assert_response :success
    body = response.body
    assert_includes body, 'id="beeper_gltf_preview"'
    assert_operator body.index('id="digital_asset_files"'), :<, body.index('id="beeper_gltf_preview"')

    shader = shader_product
    shader_asset = Spree::DigitalAsset.draft.find_by!(variant_id: shader.master.id)
    get "/admin/products/#{shader.slug}/digital_assets/#{shader_asset.id}/edit"
    assert_response :success
    refute_includes response.body, 'beeper_gltf_preview'
  end

  test 'a draft whose idle is a string or an array still renders the review and asset pages' do
    login_as(@admin, scope: :spree_user)
    ['Fan', ['Fan']].each do |idle|
      product = gltf_product(dancer.deep_merge('audio' => { 'idle' => idle }))
      asset = Spree::DigitalAsset.draft.find_by!(variant_id: product.master.id)
      get "/admin/creator_reviews/#{product.id}"
      assert_response :success
      assert_includes response.body, 'id="beeper_gltf_preview"'
      get "/admin/products/#{product.slug}/digital_assets/#{asset.id}/edit"
      assert_response :success
      assert_includes response.body, 'id="beeper_gltf_preview"'
    end
  end

  test 'the manifest guide has a glTF section with the dancer example, which validates' do
    login_as(@admin, scope: :spree_user)
    product = create(:digital_product, name: 'Scene Pack')
    get "/admin/products/#{product.slug}/digital_assets/new"
    assert_response :success
    body = CGI.unescapeHTML(response.body)
    assert_includes body, 'beeper_manifest_guide_gltf'
    assert_includes body, '"type": "gltf"'
    assert_includes body, '"scene": "dancer.glb"'
    assert_includes body, 'at most 20 MB'
    assert_equal [], Beeper::Manifests::VisualizerGltf.validate(Beeper::Gltf::EXAMPLE_MANIFEST, G.manifest_cases['summary'])
  end
end
