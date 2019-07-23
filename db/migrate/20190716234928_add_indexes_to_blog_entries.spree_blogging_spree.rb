# This migration comes from spree_blogging_spree (originally 20181022165517)
class AddIndexesToBlogEntries < ActiveRecord::Migration[4.2]
  def up
    add_index :spree_blog_entries, :title
    add_index :spree_blog_entries, :created_at
    add_index :spree_blog_entries, :published_at
    add_index :spree_blog_entries, :visible
  end

  def down
    remove_index :spree_blog_entries, :title
    remove_index :spree_blog_entries, :created_at
    remove_index :spree_blog_entries, :published_at
    remove_index :spree_blog_entries, :visible
  end
end
