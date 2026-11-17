# Scopes CMS sections to a storefront page. Every existing row belongs to the
# homepage, so the default keeps the homepage feed exactly as it was.
class AddPageKeyToHomepageSections < ActiveRecord::Migration[6.1]
  def change
    add_column :homepage_sections, :page_key, :string, null: false, default: 'home'
    add_index :homepage_sections, [:page_key, :position]
  end
end
