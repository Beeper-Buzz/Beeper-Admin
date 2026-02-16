# This migration comes from spree (originally 20140725131539)
class CreateSpreeReimbursements < ActiveRecord::Migration[4.2]
    def change
        create_table :spree_reimbursements do |t|
            t.string :number
            t.string :reimbursement_status
            t.integer :customer_return_id
            t.integer :order_id
            t.decimal :total, precision: 10, scale: 2

      t.timestamps null: false
    end
end
