# This migration comes from spree (originally 20171004223836)
class RemoveIconFromTaxons < ActiveRecord::Migration[5.1]
    def change
        if column_exists? :spree_taxons, :icon_file_name
            remove_column :spree_taxons, :icon_file_name
        end
        if column_exists? :spree_taxons, :icon_content_type
            remove_column :spree_taxons, :icon_content_type
        end
        if column_exists? :spree_taxons, :icon_file_size
            remove_column :spree_taxons, :icon_file_size
        end
        if column_exists? :spree_taxons, :icon_updated_at
            remove_column :spree_taxons, :icon_updated_at
        end
    end
end
