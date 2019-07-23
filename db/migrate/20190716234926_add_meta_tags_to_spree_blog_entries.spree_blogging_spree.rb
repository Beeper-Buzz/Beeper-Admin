# This migration comes from spree_blogging_spree (originally 20181022155517)
class AddMetaTagsToSpreeBlogEntries < ActiveRecord::Migration[5.1]
  def change
    add_column :spree_blog_entries, :meta_title, :string
    add_column :spree_blog_entries, :meta_description, :string
    add_column :spree_blog_entries, :meta_keywords, :string
  end
end
