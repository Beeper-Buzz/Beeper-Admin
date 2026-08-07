class AddCityToSpreeUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_users, :city, :string
  end
end
