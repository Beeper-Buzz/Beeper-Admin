# Beeper Admin (the iOS admin app) is com.beeper.admin. With it set, Admin app → App versions
# checks a minimum or recommended version against what the App Store serves for it. The app is
# on TestFlight only for now, so the App Store has no version yet: tick "Allow ahead of the App
# Store" and point the update link at the TestFlight invite until it is public.
# SPREE_ADMIN_NATIVE_IOS_BUNDLE_ID, read in spree_admin_native.rb, still wins when set.
SpreeAdminNative.configure do |c|
  c.ios_bundle_id = 'com.beeper.admin'
end
