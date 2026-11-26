# Beeper's admin branding. dna-admin's login, unauthorized and forbidden views read COMPANY_LOGO
# and COMPANY_BACKGROUND and fall back to the boilerplate's own images, so the fork supplies its
# own here instead of editing the inherited views. The images live in app/assets/images/beeper/,
# a folder upstream never touches, so an upstream merge cannot delete them.
#
# A value set in the environment wins. The old values (/assets/beeper_logo.png and
# /assets/beeper-login-background.jpg, from before the images moved) still map to the new files,
# so a Heroku app that has them set keeps working; once its config vars are unset or updated
# this map can go.
module BeeperBrand
  DEFAULTS = {
    'COMPANY_LOGO' => 'beeper/logo.png',
    'COMPANY_BACKGROUND' => 'beeper/login-background.jpg',
    'LOGIN_BACKGROUND' => 'beeper/login-background.jpg',
    'SITE_TITLE' => 'Beeper Admin'
  }.freeze

  MOVED = {
    '/assets/beeper_logo.png' => 'beeper/logo.png',
    'beeper_logo.png' => 'beeper/logo.png',
    '/assets/beeper-login-background.jpg' => 'beeper/login-background.jpg',
    'beeper-login-background.jpg' => 'beeper/login-background.jpg'
  }.freeze

  def self.apply!(env = ENV)
    DEFAULTS.each do |key, default|
      value = env[key].to_s.strip
      env[key] = value.empty? ? default : MOVED.fetch(value, value)
    end
  end
end

BeeperBrand.apply!
