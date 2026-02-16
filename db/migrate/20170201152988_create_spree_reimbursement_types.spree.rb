# This migration comes from spree (originally 20140731150017)
class CreateSpreeReimbursementTypes < ActiveRecord::Migration[4.2]
    def change
        create_table :spree_reimbursement_types do |t|
            t.string :name
            t.boolean :active, default: true
            t.boolean :mutable, default: true

      t.timestamps null: false
    end
end
