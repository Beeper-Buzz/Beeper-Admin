# This migration comes from spree (originally 20140713140527)
class CreateSpreeRefundReasons < ActiveRecord::Migration[4.2]
    def change
        create_table :spree_refund_reasons do |t|
            t.string :name
            t.boolean :active, default: true
            t.boolean :mutable, default: true

      t.timestamps null: false
    end
end
