require "test_helper"

# Migrations have to finish before the new code serves traffic: user saves read the profile tables.
class HerokuYmlTest < ActiveSupport::TestCase
  setup do
    @config = YAML.safe_load(Rails.root.join("heroku.yml").read)
  end

  test "a release phase runs db:migrate from the web image" do
    assert_equal "web", @config.dig("release", "image")
    assert_equal ["bundle exec rails db:migrate"], @config.dig("release", "command")
  end

  test "the web process is unchanged: assets precompile at boot, on the web dyno" do
    assert_includes @config.dig("run", "web"), "rake assets:precompile"
    assert_includes @config.dig("run", "web"), "rails server"
    assert_equal "Dockerfile", @config.dig("build", "docker", "web")
  end
end
