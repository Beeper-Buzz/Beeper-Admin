require 'test_helper'
require 'open3'

# Runs the real lib/user_tracks/track_post.py (through UserTracks::Post's production runner) on a
# synthetic groove: 6 bars at 120 bpm with a steady A minor pad, asked for a 2-bar loop. Skipped
# when the configured python (USER_TRACKS_PYTHON, default python3) lacks numpy or soundfile; the
# image has them from Debian (python3-numpy, python3-soundfile).
class UserTracks::TrackPostSmokeTest < ActiveSupport::TestCase
  GENERATOR = <<~PY.freeze
    import sys
    import numpy as np
    import soundfile as sf
    sr, bpm, bars, lead = 48000, 120.0, 6, 0.5
    beat = 60.0 / bpm
    body = bars * 4 * beat
    n = int(sr * (lead + body + 0.5))
    t = np.arange(n) / float(sr)
    on = ((t >= lead) & (t < lead + body)).astype(np.float64)
    x = np.zeros(n)
    for f in (110.0, 220.0, 261.63, 329.63):
        x += 0.1 * np.sin(2 * np.pi * f * t) * on
    for i in range(bars * 4):
        s, k = int((lead + i * beat) * sr), int(0.08 * sr)
        x[s:s + k] += (0.9 if i % 4 == 0 else 0.5) * np.exp(-np.arange(k) / (0.015 * sr)) * np.sin(2 * np.pi * 55 * np.arange(k) / float(sr))
        h, m = int((lead + (i + 0.5) * beat) * sr), int(0.02 * sr)
        x[h:h + m] += 0.15 * np.random.RandomState(i).randn(m) * np.exp(-np.arange(m) / (0.004 * sr))
    sf.write(sys.argv[1], (np.stack([x, x], axis=1) * 0.5).astype(np.float32), sr, subtype='PCM_16')
  PY

  setup do
    UserTracks.reset_config!
    UserTracks::Post.runner = nil
    skip "#{python} with numpy and soundfile is not available" unless python_ready?
    @dir = Dir.mktmpdir
  end

  teardown do
    UserTracks.reset_config!
    FileUtils.remove_entry(@dir) if @dir
  end

  def python
    UserTracks.config.python
  end

  def python_ready?
    _out, _err, status = Open3.capture3(python, '-c', 'import numpy, soundfile')
    status.success?
  rescue SystemCallError
    false
  end

  test 'cuts a 2-bar loop from a synthetic groove and answers the contract' do
    input = File.join(@dir, 'in.wav')
    out = File.join(@dir, 'loop.flac')
    _o, err, status = Open3.capture3(python, '-c', GENERATOR, input)
    assert status.success?, "generator failed: #{err}"

    track = Spree::UserTrack.new(request: { 'style' => 'synthpop', 'bars' => 2, 'bpm' => 120, 'key' => 9,
                                            'scale' => 'minor', 'timeSig' => '4/4' },
                                 generation: { 'attempts' => 1 })
    result = UserTracks::Post.call(in_path: input, out_path: out, track: track)

    %w[ok bpm bpmMeasured bpmMatch loopStartSec loopSamples sampleRate key scale keyScore keyMargin lufs peakDb
       lowNote highNote timbre].each { |field| assert result.key?(field), "#{field} in #{result.keys}" }
    assert_equal true, result['ok'], "track_post said: #{result['reason']}"
    assert_includes %w[x1 x2 x0.5], result['bpmMatch']
    assert_equal 48_000, result['sampleRate']
    expected = 2 * 4 * 0.5 * 48_000
    assert_in_delta expected, result['loopSamples'], expected * 0.02
    assert File.size?(out), 'loop.flac written'
    assert_equal 'fLaC', File.binread(out, 4)
    assert_includes %w[major minor], result['scale']
    assert_operator result['peakDb'], :<=, -0.9

    # The loop is cut on the measured beat; its tempo is reported for the engine's time-stretch.
    assert_in_delta 120.0, result['loopBpm'], 1.2
    assert_in_delta result['loopSamples'], 2 * 4 * 60.0 / result['loopBpm'] * 48_000, 2

    decision = UserTracks::Decide.call(track, result)
    assert_includes %i[ready regenerate], decision.action
    if decision.action == :ready
      assert_equal result['loopBpm'].round(3), decision.profile['bpm']
      assert_equal 'measured', decision.profile['profileSource']['bpm']
    end
  end
end
