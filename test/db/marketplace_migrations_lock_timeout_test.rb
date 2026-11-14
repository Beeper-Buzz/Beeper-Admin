require 'test_helper'

# The marketplace migrations that alter busy tables (spree_products, spree_orders) set a lock
# timeout, so a migration waiting behind a long transaction fails fast in the release phase instead
# of queueing every request behind its lock. Concurrent index builds run without it (a timed-out
# CREATE INDEX CONCURRENTLY leaves an invalid index that index_exists? would then skip), and the
# session setting is reset when the migration ends.
class MarketplaceMigrationsLockTimeoutTest < ActiveSupport::TestCase
  MIGRATIONS = %w[
    20261114130050_add_creator_columns_to_spree_products.rb
    20261114140100_add_affiliate_attribution_to_spree_orders.rb
  ].freeze

  MIGRATIONS.each do |file|
    test "#{file} sets lock_timeout first in up and resets it" do
      source = Rails.root.join('db', 'migrate', file).read
      up = source[/def up\n(.*?)\n  def down/m, 1]
      assert up, 'has an up method'
      assert_equal %(execute "SET lock_timeout = '5s'"), up.lines.first.strip
      assert_match(/ensure\n\s+execute 'RESET lock_timeout'/, up)
      up.scan(/^.*algorithm: :concurrently.*$/).each do |line|
        assert_match(/without_lock_timeout \{/, line, 'concurrent index builds run without the lock timeout')
      end
    end
  end
end
