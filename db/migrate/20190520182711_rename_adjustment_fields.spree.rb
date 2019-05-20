# This migration comes from spree (originally 20130807024302)
class RenameAdjustmentFields < ActiveRecord::Migration[4.2]
    def up
        # Add Temporary index
        unless index_exists?(:spree_adjustments, :adjustable_type)
            add_index :spree_adjustments, :adjustable_type
        end

        remove_column :spree_adjustments, :originator_id
        remove_column :spree_adjustments, :originator_type

        unless column_exists?(:spree_adjustments, :order_id)
            add_column :spree_adjustments, :order_id, :integer
        end

        # This enables the Spree::Order#all_adjustments association to work correctly
        Spree::Adjustment.reset_column_information
        Spree::Adjustment.where(adjustable_type: 'Spree::Order')
            .find_each do |adjustment|
            adjustment.update_column(:order_id, adjustment.adjustable_id)
        end

        # Remove Temporary index
        if index_exists?(:spree_adjustments, :adjustable_type)
            remove_index :spree_adjustments, :adjustable_type
        end
    end
end
