# This migration comes from spree (originally 20170323151450)
class AddMissingUniqueIndexesForUniqueAttributes < ActiveRecord::Migration[5.0]
    def change
        tables = {
            country: %i[name iso_name],
            refund_reason: %i[name],
            reimbursement_type: %i[name],
            return_authorization_reason: %i[name],
            role: %i[name],
            store: %i[code]
        }

        tables.each do |table, columns|
            table_class = "Spree::#{table.to_s.classify}".constantize
            table_name = table_class.table_name

            columns.each do |column|
                unless index_exists?(table_name, column, unique: true)
                    attributes =
                        table_class.unscoped.group(column).having('sum(1) > 1')
                            .pluck(column)
                    instances = table_class.where(column => [nil, attributes])

                    instances.find_each do |instance|
                        column_value =
                            'Unique String ' +
                                SecureRandom.urlsafe_base64(8).upcase.delete(
                                    '/+=_-'
                                )[
                                    0,
                                    8
                                ]
                        instance.send("#{column}=", column_value)
                        instance.save
                    end

                    if index_exists?(table_name, column)
                        remove_index table_name, column
                    end
                    if supports_expression_index?
                        add_index table_name, "lower(#{column})", unique: true
                    else
                        add_index table_name, column, unique: true
                    end
                end
            end
        end
    end
end
