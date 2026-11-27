require 'test_helper'

class BeeperAdminNativeTest < ActiveSupport::TestCase
  test 'App versions checks the Beeper Admin app on the App Store' do
    assert_equal ENV['SPREE_ADMIN_NATIVE_IOS_BUNDLE_ID'].presence || 'com.beeper.admin',
                 SpreeAdminNative.config.ios_bundle_id
  end
end
