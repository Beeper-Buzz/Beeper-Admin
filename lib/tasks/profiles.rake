namespace :profiles do
  desc "Read-only: counts of legacy handles the new rules would refuse, by reason, with user ids"
  task legacy_handle_report: :environment do
    LegacyHandleReport.run
  end
end
