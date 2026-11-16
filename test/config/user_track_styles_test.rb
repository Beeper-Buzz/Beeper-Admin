require 'test_helper'

# Beeper's style vocabulary (config/user_track_styles.yml): every style is complete and usable,
# and UserTracks::Styles loads all of them (it skips malformed entries silently in production).
class UserTrackStylesConfigTest < ActiveSupport::TestCase
  PATH = Rails.root.join('config', 'user_track_styles.yml')

  setup do
    @raw = YAML.safe_load(PATH.read)
    UserTracks.reset_config!
  end

  teardown { UserTracks.reset_config! }

  test 'every style has a label, a caption and a bpmRange inside 40-240' do
    styles = @raw['styles']
    assert_operator styles.size, :>=, 10
    styles.each do |style|
      id = style['id']
      assert id.to_s.match?(/\A[a-z0-9-]+\z/), "style id #{id.inspect}"
      assert style['label'].to_s.strip.present?, "#{id}: label"
      assert style['caption'].to_s.strip.present?, "#{id}: caption"
      range = style['bpmRange']
      assert range.is_a?(Array) && range.size == 2 && range.all? { |v| v.is_a?(Integer) }, "#{id}: bpmRange #{range.inspect}"
      assert range[0] <= range[1], "#{id}: bpmRange low > high"
      assert range.all? { |v| (40..240).cover?(v) }, "#{id}: bpmRange #{range.inspect} outside 40-240"
    end
    assert_equal styles.map { |s| s['id'] }.uniq, styles.map { |s| s['id'] }, 'style ids are unique'
  end

  test 'the spec styles are all there' do
    ids = @raw['styles'].map { |s| s['id'] }
    %w[retrowave deep-house lofi-hip-hop drum-and-bass trap techno synthpop ambient funk boom-bap].each do |id|
      assert_includes ids, id
    end
  end

  test 'moods are complete and every default mood exists' do
    moods = @raw['moods']
    mood_ids = moods.map { |m| m['id'] }
    moods.each { |m| assert m['label'].present? && m['words'].present?, "mood #{m['id']}" }
    @raw['styles'].each do |style|
      defaults = Array(style['defaultMoods'])
      assert defaults.size <= 2, "#{style['id']}: at most 2 default moods"
      assert (defaults - mood_ids).empty?, "#{style['id']}: unknown default moods #{defaults - mood_ids}"
    end
  end

  test 'UserTracks::Styles loads every style and mood, and prompts stay within the limit' do
    assert_equal @raw['styles'].size, UserTracks::Styles.all.size
    assert_equal @raw['moods'].size, UserTracks::Styles.moods.size
    user = create(:user)
    UserTracks::Styles.all.each do |style|
      moods = UserTracks::Styles.moods.last(2).map { |m| m[:id] }
      track = Spree::UserTrack.new(user: user, request: Spree::UserTrack.normalize_request(
        'style' => style[:id], 'moods' => moods, 'bars' => 16, 'key' => 9, 'scale' => 'minor'
      ))
      assert track.valid?, "#{style[:id]}: #{track.errors.full_messages.inspect}"
      prompt = UserTracks::Prompt.build(track)[:prompt]
      assert prompt.start_with?(style[:caption]), "#{style[:id]}: caption kept whole"
      assert prompt.length <= UserTracks::Prompt::MAX_PROMPT
    end
  end
end
