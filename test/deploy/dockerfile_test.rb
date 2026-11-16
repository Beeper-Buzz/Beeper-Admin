require "test_helper"

# The image runs lib/user_tracks/track_post.py (AI backing tracks), so it carries python3 with
# numpy and soundfile from Debian's packages.
class DockerfileTest < ActiveSupport::TestCase
  test "apt installs python3, numpy and soundfile" do
    dockerfile = Rails.root.join("Dockerfile").read.gsub("\r\n", "\n")
    install = dockerfile[/RUN apt-get update -qq && apt-get install -y \\\n(.*?)&& rm -rf/m, 1].to_s
    %w[python3 python3-numpy python3-soundfile].each do |package|
      assert_match(/^\s*#{Regexp.escape(package)} \\$/, install, "#{package} in the apt install")
    end
  end
end
