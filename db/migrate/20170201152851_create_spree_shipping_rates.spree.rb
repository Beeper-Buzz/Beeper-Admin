# This migration comes from spree (originally 20130304162240)
class CreateSpreeShippingRates < ActiveRecord::Migration[4.2]
  def up
    create_table :spree_shipping_rates do |t|
      t.belongs_to :shipment
      t.belongs_to :shipping_method
      t.boolean :selected, default: false
      t.decimal :cost, precision: 8, scale: 2
      t.timestamps null: false
    end

    def down
        # add_column :spree_shipments, :shipping_method_id, :integer
        drop_table :spree_shipping_rates
    end
end
