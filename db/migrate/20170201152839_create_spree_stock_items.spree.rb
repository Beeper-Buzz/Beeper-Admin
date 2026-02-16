# This migration comes from spree (originally 20130211190146)
class CreateSpreeStockItems < ActiveRecord::Migration[4.2]
    def change
        create_table :spree_stock_items do |t|
            t.belongs_to :stock_location
            t.belongs_to :variant
            t.integer :count_on_hand, null: false, default: 0
            t.integer :lock_version

      t.timestamps null: false
    end
end
