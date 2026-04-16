# lib/e11y/notifications/throttleable.rb
# frozen_string_literal: true

module E11y
  module Notifications
    # Concern providing alert throttling and digest accumulation for notification adapters.
    #
    # Including classes MUST implement:
    #   - #adapter_id_source → String  (stable, unique per adapter instance)
    #   - #deliver_alert(event_data) → Boolean
    #   - #deliver_digest(events:, window_start:, window_end:, total_count:, truncated:, truncated_count:) → Boolean
    #
    # Including classes MUST have instance variables:
    #   - @store          [E11y::Store::Base]
    #   - @max_event_types [Integer]
    #
    # Behaviour per event_data[:notify]:
    #   - nil                → drop silently (return true)
    #   - { alert: ... }     → immediate delivery with dedup via store
    #   - { digest: ... }    → accumulate counters; lazy-flush previous window
    #   - both               → both behaviours fire independently
    module Throttleable
      SEVERITY_RANK = { debug: 0, info: 1, success: 2, warn: 3, error: 4, fatal: 5 }.freeze

      # Main entry point — called by NotificationBase#write (or the including class directly)
      def write(event_data)
        notify = event_data[:notify]
        return true unless notify

        handle_alert(event_data, notify[:alert])   if notify[:alert]
        handle_digest(event_data, notify[:digest]) if notify[:digest]

        true
      rescue StandardError => e
        warn "[E11y] #{self.class.name} delivery error: #{e.message}"
        false
      end

      # @api private — exposed for test helpers
      #
      # Marks +current_window+ as a completed window so that when time advances
      # past it, +maybe_flush_digest+ will pick it up as the previous window.
      # Copies accumulated state from +current_window+ into a stable snapshot
      # keyed under +previous_window+ as a secondary record (used by flush).
      # In tests this simulates a natural window rollover without sleeping.
      def copy_window_to_previous!(current_window, previous_window, digest_cfg)
        interval = digest_cfg[:digest] ? digest_cfg[:digest][:interval] : digest_cfg[:interval]
        ttl      = interval * 2

        # Ensure current_window has an index so maybe_flush_digest triggers.
        existing = @store.get(digest_key(current_window, "__index__"))
        @store.set(digest_key(current_window, "__index__"), [], ttl: ttl) unless existing

        index = @store.get(digest_key(current_window, "__index__")) || []

        # Mirror to previous_window slot (kept for symmetry / multi-node scenarios).
        @store.set(digest_key(previous_window, "__index__"), index, ttl: ttl)

        index.each do |name|
          count = @store.get(digest_key(current_window, "#{name}:count")) || 0
          sev   = @store.get(digest_key(current_window, "#{name}:severity"))
          @store.set(digest_key(previous_window, "#{name}:count"), count, ttl: ttl)
          @store.set(digest_key(previous_window, "#{name}:severity"), sev, ttl: ttl) if sev
        end

        overflow = @store.get(digest_key(current_window, "__overflow__")) || 0
        @store.set(digest_key(previous_window, "__overflow__"), overflow, ttl: ttl) if overflow.positive?
      end

      private

      # ── Alert ─────────────────────────────────────────────────────────────────

      def handle_alert(event_data, alert_cfg)
        fp  = compute_fingerprint(event_data, alert_cfg[:fingerprint])
        key = "e11y:alert:#{adapter_id}:#{fp}"

        return unless @store.set_if_absent(key, true, ttl: alert_cfg[:throttle_window])

        deliver_alert(event_data)
      end

      def compute_fingerprint(event_data, fields)
        fields.map { |f| dig_field(event_data, f) }.join(":")
      end

      def dig_field(event_data, field)
        case field
        when Symbol
          event_data[field].to_s
        when String
          parts = field.split(".")
          parts.reduce(event_data) { |h, k| h.is_a?(Hash) ? (h[k.to_sym] || h[k]) : nil }.to_s
        end
      end

      # ── Digest ────────────────────────────────────────────────────────────────

      def handle_digest(event_data, digest_cfg)
        record_for_digest(event_data, digest_cfg)
        maybe_flush_digest(digest_cfg)
      end

      def record_for_digest(event_data, digest_cfg)
        interval = digest_cfg[:interval]
        window   = current_window(interval)
        ttl      = interval * 2
        name     = event_data[:event_name].to_s

        seen_key = digest_key(window, "#{name}:seen")
        if @store.set_if_absent(seen_key, true, ttl: ttl)
          index = @store.fetch(digest_key(window, "__index__"), ttl: ttl) { [] }
          if index.size < @max_event_types
            @store.set(digest_key(window, "__index__"), (index + [name]).uniq, ttl: ttl)
          else
            @store.increment(digest_key(window, "__overflow__"), ttl: ttl)
            return
          end
        end

        @store.increment(digest_key(window, "#{name}:count"), ttl: ttl)
        update_max_severity(window, name, event_data[:severity], ttl)
      end

      def maybe_flush_digest(digest_cfg)
        interval    = digest_cfg[:interval]
        current_win = current_window(interval)
        previous_win = current_win - interval

        return unless @store.get(digest_key(previous_win, "__index__"))

        lock_key = digest_key(previous_win, "__lock__")
        return unless @store.set_if_absent(lock_key, true, ttl: interval)

        flush_digest_window(previous_win, interval)
      end

      def flush_digest_window(window, interval)
        index    = @store.get(digest_key(window, "__index__")) || []
        overflow = @store.get(digest_key(window, "__overflow__")).to_i

        events = index.map do |name|
          count    = @store.get(digest_key(window, "#{name}:count")).to_i
          severity = @store.get(digest_key(window, "#{name}:severity"))&.to_sym
          { event_name: name, count: count, severity: severity }
        end

        events.sort_by! { |e| -e[:count] }

        total = events.sum { |e| e[:count] } + overflow

        deliver_digest(
          events: events,
          window_start: Time.at(window),
          window_end: Time.at(window + interval),
          total_count: total,
          truncated: overflow.positive?,
          truncated_count: overflow
        )
      end

      def update_max_severity(window, name, severity, ttl)
        key     = digest_key(window, "#{name}:severity")
        current = @store.get(key)&.to_sym

        return if current && SEVERITY_RANK[current].to_i >= SEVERITY_RANK[severity].to_i

        @store.set(key, severity.to_s, ttl: ttl)
      end

      # ── Helpers ───────────────────────────────────────────────────────────────

      def adapter_id
        @adapter_id ||= begin
          require "digest"
          Digest::SHA256.hexdigest(adapter_id_source)[0..7]
        end
      end

      def current_window(interval)
        now = Time.now.to_i
        (now / interval) * interval
      end

      def digest_key(window, suffix)
        "e11y:d:#{adapter_id}:#{window}:#{suffix}"
      end
    end
  end
end
