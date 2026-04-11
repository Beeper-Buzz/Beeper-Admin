class AddCreatorFieldsToSpreeUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_users, :is_creator,   :boolean, default: false, null: false
    add_column :spree_users, :display_name, :string
    add_column :spree_users, :bio,          :text
    add_column :spree_users, :avatar_url,   :string
    add_column :spree_users, :banner_url,   :string
    add_column :spree_users, :website,      :string
    add_column :spree_users, :instagram,    :string
    add_column :spree_users, :tiktok,       :string
    add_column :spree_users, :youtube,      :string
    add_column :spree_users, :soundcloud,   :string
    add_column :spree_users, :bandcamp,     :string

    add_index :spree_users, :is_creator, where: "is_creator = true"
    add_index :spree_users, :display_name, unique: true, where: "display_name IS NOT NULL"
  end
end
