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

  # Assets compile in the Docker build (Dockerfile), never on a booting dyno: precompiling at boot
  # pushed a 512 MB dyno into R14s and H12s.
  test "the web process only starts the server; assets are compiled in the image" do
    assert_includes @config.dig("run", "web"), "rails server"
    refute_includes @config.dig("run", "web"), "assets:precompile"
    assert_equal "Dockerfile", @config.dig("build", "docker", "web")
    assert_includes Rails.root.join("Dockerfile").read, "rake assets:precompile"
  end
end
