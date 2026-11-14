require 'test_helper'

# config/beeper_effects.yml mirrors the app's effect definitions (BeeperNative src/data/effects.ts
# and EFFECT_ORDER in src/atoms/studio.ts). When the app adds an effect or changes a range, update
# the YAML and this list together.
class Beeper::EffectsTest < ActiveSupport::TestCase
  APP_EFFECTS = {
    'drive' => %w[amount tone mix],
    'crush' => %w[bits downsample noise mix],
    'eq' => %w[low mid midFreq high],
    'chorus' => %w[rate depth mix],
    'phaser' => %w[rate depth feedback mix],
    'echo' => %w[time sync division feedback tone pingPong mix],
    'reverb' => %w[size damping width mix],
    'pump' => %w[depth shape division],
    'compressor' => %w[threshold ratio attack release makeup]
  }.freeze

  test 'the nine effect ids, in the app order, with the app params' do
    assert_equal APP_EFFECTS.keys, Beeper::Effects.ids
    APP_EFFECTS.each do |id, params|
      assert_equal params, Beeper::Effects.params(id).keys, id
    end
  end

  test 'ranges and defaults match the app' do
    {
      %w[drive amount] => [0, 1, 0.4],
      %w[crush bits] => [2, 16, 8],
      %w[crush downsample] => [1, 32, 4],
      %w[eq low] => [-12, 12, 0],
      %w[eq midFreq] => [200, 5000, 1000],
      %w[chorus rate] => [0.05, 5, 0.8],
      %w[phaser feedback] => [0, 0.9, 0.5],
      %w[echo time] => [0.02, 2, 0.375],
      %w[echo division] => [0, 5, 2],
      %w[echo feedback] => [0, 0.95, 0.4],
      %w[echo pingPong] => [0, 1, 0],
      %w[reverb mix] => [0, 1, 0.3],
      %w[pump division] => [0, 3, 0],
      %w[compressor threshold] => [-60, 0, -18],
      %w[compressor ratio] => [1, 20, 4],
      %w[compressor attack] => [0.1, 100, 10],
      %w[compressor release] => [10, 1000, 120],
      %w[compressor makeup] => [0, 24, 4]
    }.each do |(id, param), (min, max, default)|
      meta = Beeper::Effects.params(id).fetch(param)
      assert_equal [min, max, default], [meta['min'], meta['max'], meta['default']], "#{id}.#{param}"
    end
  end

  test 'the definitions are frozen' do
    assert Beeper::Effects::DEFINITIONS.frozen?
    assert Beeper::Effects.params('reverb').frozen?
  end
end
