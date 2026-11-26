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

  # Assets are precompiled into the image (Dockerfile), so the web dyno only starts the server.
  test "the web process starts the server without precompiling assets" do
    assert_includes @config.dig("run", "web"), "rails server"
    refute_includes @config.dig("run", "web"), "assets:precompile"
    assert_equal "Dockerfile", @config.dig("build", "docker", "web")
    assert_match(/assets:precompile/, Rails.root.join("Dockerfile").read)
  end
end
