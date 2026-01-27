# frozen_string_literal: true

module E11y
  module Middleware
    # Routing middleware routes events to appropriate adapters based on retention policies.
    #
    # This is the FINAL middleware in the pipeline (adapters zone),
    # running AFTER all processing (TraceContext, Validation, PII Filtering,
    # Rate Limiting, Sampling, Versioning).
    #
    # **Routing Logic (Priority Order):**
    # 1. **Explicit adapters** - event_data[:adapters] bypasses routing rules
    # 2. **Routing rules** - lambdas from config.routing_rules
    # 3. **Fallback adapters** - config.fallback_adapters if no rule matches
    #
    # **Routing Rules (Lambdas):**
    # Rules are evaluated in order. Each rule receives event_data hash and returns:
    # - Symbol (adapter name) - route to this adapter
    # - Array<Symbol> (adapter names) - route to multiple adapters
    # - nil - rule doesn't match, try next rule
    #
    # @see ADR-004 §14 (Retention-Based Routing)
    # @see ADR-009 §6 (Cost Optimization via Routing)
    # @see UC-019 (Retention-Based Event Routing)
    #
    # @example Explicit adapters (bypass routing)
    #   event_data = {
    #     event_name: 'payment.completed',
    #     adapters: [:audit_encrypted, :loki],  # ← Explicit
    #     retention_until: '2027-01-21T...'
    #   }
    #   # Routes to: [:audit_encrypted, :loki] (ignores routing rules)
    #
    # @example Audit event routing (via rules)
    #   event_data = {
    #     event_name: 'user.deleted',
    #     audit_event: true,
    #     retention_until: '2033-01-21T...'
    #   }
    #   # Rule: ->(e) { :audit_encrypted if e[:audit_event] }
    #   # Routes to: [:audit_encrypted]
    #
    # @example Retention-based routing
    #   event_data = {
    #     event_name: 'order.placed',
    #     retention_until: '2026-04-21T...'  # 90 days
    #   }
    #   # Rule: ->(e) { days > 30 ? :s3_standard : :loki }
    #   # Routes to: [:s3_standard]
    class Routing < Base
      middleware_zone :adapters

      # Routes event to appropriate adapters based on retention policies.
      #
      # @param event_data [Hash] The event data to route
      # @option event_data [Array<Symbol>] :adapters Explicit adapter names (optional, bypasses routing)
      # @option event_data [String] :retention_until ISO8601 timestamp (optional, for routing rules)
      # @option event_data [Boolean] :audit_event Audit event flag (optional, for routing rules)
      # @option event_data [Symbol] :severity Event severity (optional, for routing rules)
      # @return [Hash, nil] Event data (passed to next middleware), or nil if dropped
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      # Routing logic requires adapter selection, iteration with error handling,
      # metadata enrichment, and metrics tracking
      def call(event_data)
        # Handle nil from upstream middleware (e.g., rate limiting, sampling)
        return nil unless event_data

        # 1. Determine target adapters (explicit or via routing rules)
        target_adapters = if event_data[:adapters]&.any?
                            # Explicit adapters bypass routing rules
                            event_data[:adapters]
                          else
                            # Apply routing rules from configuration
                            apply_routing_rules(event_data)
                          end

        # 1.5. Validate audit events have proper routing (UC-012 compliance requirement)
        validate_audit_routing!(event_data, target_adapters)

        # 2. Write to selected adapters
        target_adapters.each do |adapter_name|
          adapter = E11y.configuration.adapters[adapter_name]
          next unless adapter

          begin
            adapter.write(event_data)
            increment_metric("e11y.middleware.routing.write_success", adapter: adapter_name)
          rescue StandardError => e
            # Log routing error but don't fail pipeline
            warn "E11y routing error for adapter #{adapter_name}: #{e.message}"
            increment_metric("e11y.middleware.routing.write_error", adapter: adapter_name)
          end
        end

        # 3. Add routing metadata to event_data
        event_data[:routing] = {
          adapters: target_adapters,
          routed_at: Time.now.utc,
          routing_type: event_data[:adapters]&.any? ? :explicit : :rules
        }

        # 4. Increment metrics
        increment_metric("e11y.middleware.routing.routed",
                         adapters_count: target_adapters.size,
                         routing_type: event_data[:routing][:routing_type])

        # 5. Log routing decision (for debugging)
        log_routing_decision(event_data, target_adapters) if debug_enabled?

        # 6. Pass to next app (if any)
        @app&.call(event_data)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      private

      # Apply routing rules from configuration.
      #
      # Evaluates routing rules in order until a match is found.
      # Each rule is a lambda that receives event_data and returns:
      # - Symbol (adapter name) - route to this adapter
      # - Array<Symbol> (adapter names) - route to multiple adapters
      # - nil - rule doesn't match, try next rule
      #
      # @param event_data [Hash] Event data with retention_until, audit_event, severity, etc.
      # @return [Array<Symbol>] Target adapter names
      #
      # @example
      #   rules = [
      #     ->(event) { :audit_encrypted if event[:audit_event] },
      #     ->(event) {
      #       days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      #       days > 90 ? :s3_glacier : :loki
      #     }
      #   ]
      #
      #   apply_routing_rules(event_data)
      #   # => [:audit_encrypted] or [:loki] or [:s3_glacier]
      def apply_routing_rules(event_data)
        matched_adapters = []

        # Apply each rule, collect matched adapters
        rules = E11y.configuration.routing_rules || []
        rules.each do |rule|
          result = rule.call(event_data)
          matched_adapters.concat(Array(result)) if result
        rescue StandardError => e
          # Log rule evaluation error but continue
          warn "E11y routing rule error: #{e.message}"
        end

        # Track whether fallback was used (for audit validation)
        if matched_adapters.any?
          event_data[:routing_used_fallback] = false
          matched_adapters.uniq
        else
          event_data[:routing_used_fallback] = true
          E11y.configuration.fallback_adapters || [:stdout]
        end
      end

      # Log routing decision for debugging.
      #
      # @param event_data [Hash] Event data
      # @param adapters [Array<Symbol>] Target adapters
      # @return [void]
      def log_routing_decision(event_data, adapters)
        # TODO: Replace with structured logging
        # Rails.logger.debug "[E11y] Routing: #{event_data[:event_name]} → #{adapters.inspect}"
      end

      # Check if debug logging is enabled.
      #
      # @return [Boolean]
      def debug_enabled?
        # TODO: Read from configuration
        # E11y.configuration.debug_enabled
        false # Disabled for now
      end

      # Placeholder for metrics instrumentation.
      #
      # @param metric_name [String] Metric name
      # @param tags [Hash] Metric tags
      # @return [void]
      def increment_metric(_metric_name, **_tags)
        # TODO: Integrate with Yabeda/Prometheus
        # Yabeda.e11y.middleware_routing_routed.increment(tags)
      end

      # Validate audit events have proper routing configuration.
      #
      # Audit events MUST be routed via explicit adapters OR routing rules.
      # Relying on fallback routing (no rule matched) is a compliance configuration error.
      #
      # @param event_data [Hash] Event data
      # @param target_adapters [Array<Symbol>] Target adapters
      # @raise [E11y::Error] if audit event misconfigured
      # @return [void]
      def validate_audit_routing!(event_data, target_adapters)
        return unless event_data[:audit_event]

        # Audit events are valid if:
        # 1. They have explicit adapters (non-empty), OR
        # 2. They matched a routing rule (routing_used_fallback = false)
        
        has_explicit_adapters = event_data[:adapters]&.any?
        return if has_explicit_adapters # Explicit adapters → valid

        # Check if fallback was used (set by apply_routing_rules)
        used_fallback = event_data[:routing_used_fallback]
        return unless used_fallback

        # CRITICAL: Audit event using fallback routing (no rule matched!)
        error_message = <<~ERROR
          [E11y] CRITICAL: Audit event has no routing configuration!
          
          Event: #{event_data[:event_name]}
          Routed to: #{target_adapters.inspect} (fallback adapters)
          
          Audit events MUST be explicitly routed to compliance-grade storage.
          
          Fix options:
          1. Add explicit adapters: `adapters :audit_encrypted`
          2. Configure routing rule: `config.routing_rules = [->(e) { :audit_encrypted if e[:audit_event] }]`
          
          See UC-012 Audit Trail documentation for details.
        ERROR

        raise E11y::Error, error_message
      end
    end
  end
end
