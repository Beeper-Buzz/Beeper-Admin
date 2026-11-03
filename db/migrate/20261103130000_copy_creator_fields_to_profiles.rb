# Copies the creator columns on spree_users into spree_user_profiles (see LegacyCreatorProfiles).
# Invalid legacy values are logged and skipped. Down deletes the copied rows nobody changed since.
class CopyCreatorFieldsToProfiles < ActiveRecord::Migration[6.1]
  def up
    Spree::User.reset_column_information
    Spree::UserProfile.reset_column_information
    LegacyCreatorProfiles.copy!(logger: Logger.new($stdout))
  end

  def down
    LegacyCreatorProfiles.remove!
  end
end
