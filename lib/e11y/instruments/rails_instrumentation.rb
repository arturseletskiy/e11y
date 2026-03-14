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
        "sql.active_record" => "E11y::Events::Rails::Database::Query",
        "process_action.action_controller" => "E11y::Events::Rails::Http::Request",
        "render_template.action_view" => "E11y::Events::Rails::View::Render",
        "send_file.action_controller" => "E11y::Events::Rails::Http::SendFile",
        "redirect_to.action_controller" => "E11y::Events::Rails::Http::Redirect",
        "cache_read.active_support" => "E11y::Events::Rails::Cache::Read",
        "cache_write.active_support" => "E11y::Events::Rails::Cache::Write",
        "cache_delete.active_support" => "E11y::Events::Rails::Cache::Delete",
        "enqueue.active_job" => "E11y::Events::Rails::Job::Enqueued",
        "enqueue_at.active_job" => "E11y::Events::Rails::Job::Scheduled",
        "perform_start.active_job" => "E11y::Events::Rails::Job::Started",
        # perform.active_job: Completed on success, Failed on exception (routed in track_rails_event)
        "perform.active_job" => "E11y::Events::Rails::Job::Completed"
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
      #
      # **Architecture Note**: We pass the entire payload to the event class.
      # Each event class defines its own schema (via dry-schema), which:
      # 1. **Type-checks** fields automatically
      # 2. **Filters** only relevant fields (unknown fields ignored)
      # 3. **Validates** payload structure
      #
      # This eliminates the need for manual whitelisting (DRY principle).
      # PII filtering happens in the middleware pipeline, not here.
      #
      # @param asn_pattern [String] ActiveSupport::Notifications pattern
      # @param e11y_event_class_name [String] E11y event class name
      # @return [void]
      #
      # @example
      #   # ASN payload: { controller: "Users", action: "index", password: "secret" }
      #   # Event schema: schema { required(:controller).string; required(:action).string }
      #   # Result: { controller: "Users", action: "index" } - password filtered by schema
      def self.subscribe_to_event(asn_pattern, e11y_event_class_name)
        ActiveSupport::Notifications.subscribe(asn_pattern) do |name, start, finish, _id, payload|
          track_rails_event(name, start, finish, payload, e11y_event_class_name)
        rescue StandardError => e
          warn "[E11y] Failed to track Rails event #{name}: #{e.message}"
        end
      end

      def self.track_rails_event(name, start, finish, payload, e11y_event_class_name)
        duration = (finish - start) * 1000
        extracted_payload = extract_job_info_from_object(payload)

        # perform.active_job: route to Failed when job raised exception
        if name == "perform.active_job" && job_failed?(payload)
          e11y_event_class = resolve_event_class("E11y::Events::Rails::Job::Failed")
          extracted_payload = extracted_payload.merge(extract_job_exception_info(payload))
        else
          e11y_event_class = resolve_event_class(e11y_event_class_name)
          extracted_payload = extracted_payload.merge(severity: :error) if process_action_error?(name, payload)
        end

        return unless e11y_event_class

        e11y_event_class.track(event_name: name, duration: duration, **extracted_payload)
      end

      def self.process_action_error?(name, payload)
        name == "process_action.action_controller" && (payload[:exception] || payload["exception"])
      end

      def self.job_failed?(payload)
        payload[:exception].present? || payload["exception"].present?
      end

      # Extract error_class and error_message from ActiveJob exception payload.
      # Rails passes exception as ["ErrorClass", "message"] or exception_object.
      def self.extract_job_exception_info(payload)
        ex = payload[:exception] || payload["exception"]
        return {} unless ex

        if ex.is_a?(Array) && ex.size >= 2
          { error_class: ex[0].to_s, error_message: ex[1].to_s }
        elsif ex.respond_to?(:class) && ex.respond_to?(:message)
          { error_class: ex.class.name, error_message: ex.message.to_s }
        else
          {}
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

      # Extract job info from job object (ActiveJob events)
      #
      # ActiveJob events pass job object, not flattened fields.
      # This method extracts relevant fields from job object.
      #
      # @param payload [Hash] ASN event payload
      # @return [Hash] Payload with extracted job info
      def self.extract_job_info_from_object(payload)
        # Return early if no job object
        return payload unless payload[:job]

        # Clone payload to avoid mutation
        result = payload.dup
        job = result.delete(:job)

        # Extract job fields if not already present
        result[:job_class] ||= job.class.name
        result[:job_id] ||= job.job_id
        result[:queue] ||= job.queue_name

        result
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
