# This migration comes from spree (originally 20141217215630)
class UpdateProductSlugIndex < ActiveRecord::Migration[4.2]
    def change
        if index_exists?(:spree_products, :slug)
            remove_index :spree_products, :slug
        end
        add_index :spree_products, :slug, unique: true
    end
end
