# This migration comes from spree_blogging_spree (originally 20130313213904)
class AddAuthorToBlogEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :spree_blog_entries, :author, :string
  end
end
