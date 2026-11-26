require 'test_helper'

# config/initializers/beeper_brand.rb: Beeper's admin branding on top of dna-admin's neutral views.
class BeeperBrandTest < ActiveSupport::TestCase
  test 'unset or blank values get the Beeper defaults' do
    env = { 'COMPANY_LOGO' => '', 'SITE_TITLE' => '  ' }
    BeeperBrand.apply!(env)
    assert_equal 'beeper/logo.png', env['COMPANY_LOGO']
    assert_equal 'beeper/login-background.jpg', env['COMPANY_BACKGROUND']
    assert_equal 'beeper/login-background.jpg', env['LOGIN_BACKGROUND']
    assert_equal 'Beeper Admin', env['SITE_TITLE']
  end

  test 'the paths from before the images moved map to the new files' do
    env = { 'COMPANY_LOGO' => '/assets/beeper_logo.png',
            'COMPANY_BACKGROUND' => '/assets/beeper-login-background.jpg',
            'LOGIN_BACKGROUND' => 'beeper-login-background.jpg' }
    BeeperBrand.apply!(env)
    assert_equal 'beeper/logo.png', env['COMPANY_LOGO']
    assert_equal 'beeper/login-background.jpg', env['COMPANY_BACKGROUND']
    assert_equal 'beeper/login-background.jpg', env['LOGIN_BACKGROUND']
  end

  test 'any other value set in the environment wins' do
    env = { 'COMPANY_LOGO' => 'other/logo.png', 'SITE_TITLE' => 'Staging Admin' }
    BeeperBrand.apply!(env)
    assert_equal 'other/logo.png', env['COMPANY_LOGO']
    assert_equal 'Staging Admin', env['SITE_TITLE']
  end

  test 'every default is a file in app/assets/images' do
    BeeperBrand::DEFAULTS.values_at('COMPANY_LOGO', 'COMPANY_BACKGROUND', 'LOGIN_BACKGROUND').each do |path|
      assert Rails.root.join('app/assets/images', path).file?, "missing app/assets/images/#{path}"
    end
  end
end
