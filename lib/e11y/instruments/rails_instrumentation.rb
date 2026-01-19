# frozen_string_literal: true

module E11y
  module Instruments
    # Rails Instrumentation (ActiveSupport::Notifications → E11y)
    #
    # Subscribes to Rails internal events (ActiveSupport::Notifications)
    # and converts them to E11y events for unified observability.
    #
    # **Unidirectional Flow:** ASN → E11y
    #
    # @example Basic usage
    #   # Automatically enabled by E11y::Railtie if config.rails_instrumentation.enabled = true
    #   E11y::Instruments::RailsInstrumentation.setup!
    #
    # @example Custom event mapping
    #   E11y.configure do |config|
    #     config.rails_instrumentation do
    #       event_class_for 'sql.active_record', MyApp::CustomQueryEvent
    #       ignore_event 'cache_read.active_support'
    #     end
    #   end
    #
    # @see ADR-008 §4.1 (Unidirectional Flow ASN → E11y)
    # @see UC-016 (Rails Logger Migration)
    class RailsInstrumentation
      # Built-in event mappings (ASN pattern → E11y Event class)
      #
      # These are defaults that can be overridden via config.event_class_for
      #
      # @return [Hash<String, Class>] Event mappings
      DEFAULT_RAILS_EVENT_MAPPING = {
        "sql.active_record" => "Events::Rails::Database::Query",
        "process_action.action_controller" => "Events::Rails::Http::Request",
        "render_template.action_view" => "Events::Rails::View::Render",
        "send_file.action_controller" => "Events::Rails::Http::SendFile",
        "redirect_to.action_controller" => "Events::Rails::Http::Redirect",
        "cache_read.active_support" => "Events::Rails::Cache::Read",
        "cache_write.active_support" => "Events::Rails::Cache::Write",
        "cache_delete.active_support" => "Events::Rails::Cache::Delete",
        "enqueue.active_job" => "Events::Rails::Job::Enqueued",
        "enqueue_at.active_job" => "Events::Rails::Job::Scheduled",
        "perform_start.active_job" => "Events::Rails::Job::Started",
        "perform.active_job" => "Events::Rails::Job::Completed"
      }.freeze

      # Setup Rails instrumentation
      #
      # Subscribes to ActiveSupport::Notifications events and converts them to E11y events.
      #
      # @return [void]
      def self.setup!
        return unless E11y.config.rails_instrumentation&.enabled

        # Subscribe to each configured event pattern
        event_mapping.each do |asn_pattern, e11y_event_class_name|
          next if ignored?(asn_pattern)

          subscribe_to_event(asn_pattern, e11y_event_class_name)
        end
      end

      # Subscribe to a specific ASN event
      # @param asn_pattern [String] ActiveSupport::Notifications pattern
      # @param e11y_event_class_name [String] E11y event class name
      # @return [void]
      def self.subscribe_to_event(asn_pattern, e11y_event_class_name)
        ActiveSupport::Notifications.subscribe(asn_pattern) do |name, start, finish, id, payload|
          # Convert ASN event → E11y event
          duration = (finish - start) * 1000 # Convert to milliseconds

          # Resolve event class (string → constant)
          e11y_event_class = resolve_event_class(e11y_event_class_name)
          next unless e11y_event_class

          # Track E11y event with extracted payload
          e11y_event_class.track(
            event_name: name,
            duration: duration,
            **extract_relevant_payload(payload)
          )
        rescue StandardError => e
          # Don't crash the app if event tracking fails
          warn "[E11y] Failed to track Rails event #{name}: #{e.message}"
        end
      end

      # Get final event mapping (after config overrides)
      # @return [Hash<String, String>] Event mappings
      def self.event_mapping
        @event_mapping ||= begin
          mapping = DEFAULT_RAILS_EVENT_MAPPING.dup

          # Apply custom mappings from config (Devise-style overrides)
          custom_mappings = E11y.config.rails_instrumentation&.custom_mappings || {}
          custom_mappings.each do |pattern, event_class|
            mapping[pattern] = event_class.name
          end

          mapping
        end
      end

      # Check if event pattern should be ignored
      # @param pattern [String] ASN event pattern
      # @return [Boolean] true if should be ignored
      def self.ignored?(pattern)
        ignore_list = E11y.config.rails_instrumentation&.ignore_events || []
        ignore_list.include?(pattern)
      end

      # Extract relevant payload fields from ASN event
      #
      # Filters out PII and noisy fields, keeping only relevant data.
      #
      # @param payload [Hash] ASN event payload
      # @return [Hash] Filtered payload
      def self.extract_relevant_payload(payload)
        # Extract only relevant fields (avoid PII, reduce noise)
        # This is a basic implementation - specific event classes can override
        payload.slice(
          :controller, :action, :format, :status,
          :allocations, :db_runtime, :view_runtime,
          :name, :sql, :connection_id,
          :key, :hit,
          :job_class, :job_id, :queue
        )
      end

      # Resolve event class from string name
      # @param class_name [String] Event class name
      # @return [Class, nil] Event class or nil if not found
      def self.resolve_event_class(class_name)
        class_name.constantize
      rescue NameError => e
        warn "[E11y] Event class not found: #{class_name} (#{e.message})"
        nil
      end
    end
  end
end
