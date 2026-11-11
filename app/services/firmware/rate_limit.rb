module Firmware
  # Fixed-window counters for the public firmware endpoints (Firmware.config.rate_limits), one
  # atomic upsert per check in Postgres, the same design as AppFeedback::RateLimit. IPs are stored
  # only as an HMAC. Fails open: a counter error never blocks an update.
  module RateLimit
    module_function

    # Counts this attempt under every rule ({ report_ip: key, report_device: key }); false once
    # any is over its limit, after giving back the hits taken so a refusal by one rule doesn't
    # use up another. Blank keys are skipped.
    def allow_all?(keys, now: Time.current)
      taken = []
      keys.each do |rule_name, key|
        next if key.blank?

        rule = Firmware.config.rate_limits.fetch(rule_name)
        counter_key = "#{rule_name}:#{key}"
        hits = hit(counter_key, rule[:window], now)
        taken << counter_key
        next if hits <= rule[:limit]

        give_back(taken)
        return false
      end
      true
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("[firmware] rate limit check failed: #{e.class}")
      true
    end

    def ip_key(ip)
      return if ip.blank?

      OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base.to_s, "firmware-ip:#{ip}")
    end

    def hit(key, window, now)
      table = Firmware::RateCounter.quoted_table_name
      sql = Firmware::RateCounter.sanitize_sql_array([<<~SQL, { key: key, now: now, cutoff: now - window }])
        INSERT INTO #{table} (key, window_started_at, hits)
        VALUES (:key, :now, 1)
        ON CONFLICT (key) DO UPDATE SET
          hits = CASE WHEN #{table}.window_started_at <= :cutoff THEN 1 ELSE #{table}.hits + 1 END,
          window_started_at = CASE WHEN #{table}.window_started_at <= :cutoff THEN :now ELSE #{table}.window_started_at END
        RETURNING hits
      SQL
      connection = Firmware::RateCounter.connection
      hits = connection.uncached { connection.select_value(sql) }.to_i
      prune(now - (2 * longest_window)) if rand < 0.01
      hits
    end

    # Rules share one table, so pruning keeps rows for twice the longest window: pruning by the
    # current rule's window (1 h for check_ip) would delete live 24 h report_device counters.
    def longest_window
      Firmware.config.rate_limits.values.map { |rule| rule[:window] }.max
    end

    def give_back(counter_keys)
      Firmware::RateCounter.where(key: counter_keys).where('hits > 0').update_all('hits = hits - 1')
    end

    def prune(before)
      Firmware::RateCounter.where('window_started_at < ?', before).delete_all
    end
  end
end
