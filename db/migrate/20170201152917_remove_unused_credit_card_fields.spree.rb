# This migration comes from spree (originally 20131001013410)
class RemoveUnusedCreditCardFields < ActiveRecord::Migration[4.2]
    def up
        if column_exists?(:spree_credit_cards, :start_month)
            remove_column :spree_credit_cards, :start_month
        end
        if column_exists?(:spree_credit_cards, :start_year)
            remove_column :spree_credit_cards, :start_year
        end
        if column_exists?(:spree_credit_cards, :issue_number)
            remove_column :spree_credit_cards, :issue_number
        end
    end
    def down
        add_column :spree_credit_cards, :start_month, :string
        add_column :spree_credit_cards, :start_year, :string
        add_column :spree_credit_cards, :issue_number, :string
    end

    def column_exists?(table, column)
        ApplicationRecord.connection.column_exists?(table, column)
    end
end
