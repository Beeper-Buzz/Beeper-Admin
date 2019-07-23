# This migration comes from spree_blogging_spree (originally 20181022165517)
class AddIndexToPermalinks < ActiveRecord::Migration[4.2]
  def up
    add_index :spree_blog_entries, :permalink
  end

  def down
    remove_index :spree_blog_entries, :permalink
  end
end
