# Read-only report behind `rake profiles:legacy_handle_report`: which legacy spree_users.display_name
# values the new handle rules would refuse, by reason. Prints counts and user ids only.
#
# Runs before the profile tables exist too, so it can size the problem ahead of a deploy. The
# whole run is a Postgres READ ONLY transaction, so it can't write even by accident.
class LegacyHandleReport
  REASONS = %i[invalid reserved not_allowed taken].freeze

  def self.run(io: $stdout)
    new(io).run
  end

  def self.read_only
    Spree::User.transaction(requires_new: true) do
      Spree::User.connection.execute("SET TRANSACTION READ ONLY")
      yield
      raise ActiveRecord::Rollback
    end
  end

  def initialize(io)
    @io = io
  end

  def run
    self.class.read_only { print_report(tally) }
  end

  private

  def legacy_rows
    Spree::User.unscoped.where(deleted_at: nil).where.not(display_name: [nil, ""]).order(:id)
               .pluck(:id, :is_creator, :display_name)
  end

  def tally
    owners = existing_handle_owners
    rows = legacy_rows
    refused = REASONS.index_with { [] }
    rows.each do |id, is_creator, display_name|
      handle = Profiles::HandlePolicy.normalize(display_name)
      reason = Profiles::HandlePolicy.refusal(handle) || (:taken if owners.fetch(handle, id) != id)
      if reason
        refused[reason] << [id, is_creator]
      else
        owners[handle] = id
      end
    end
    { total: rows.size, refused: refused }
  end

  # handle => user id, for handles profiles already hold. Empty before the table exists.
  def existing_handle_owners
    return {} unless Spree::UserProfile.table_exists?

    Spree::UserProfile.with_handle.pluck(:handle, :user_id).map { |handle, user_id| [handle.downcase, user_id] }.to_h
  end

  def print_report(tally)
    refused = tally[:refused]
    all = refused.values.flatten(1)
    @io.puts "Legacy handle report (read-only)"
    @io.puts "users with a legacy handle: #{tally[:total]}"
    @io.puts "would copy: #{tally[:total] - all.size}"
    @io.puts "refused: #{all.size} (creators: #{creators(all)})"
    refused.each do |reason, rows|
      @io.puts "#{reason}: #{rows.size} (creators: #{creators(rows)})"
      @io.puts "  user ids: #{rows.map(&:first).sort.join(', ')}" if rows.any?
    end
  end

  def creators(rows)
    rows.count { |_id, is_creator| is_creator }
  end
end
