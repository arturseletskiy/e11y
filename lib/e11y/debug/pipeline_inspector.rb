# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module E11y
  module Debug
    class PipelineInspector
      class << self
        def trace_event(event_class, **payload)
          event_data = build_event_data(event_class, payload)
          pipeline = build_tracing_pipeline
          pipeline.call(event_data)
        end

        private

        def build_event_data(event_class, payload)
          {
            event_class: event_class,
            event_name: event_class.respond_to?(:event_name) ? event_class.event_name : event_class.name,
            payload: payload,
            severity: event_class.respond_to?(:severity) ? event_class.severity : :info,
            version: event_class.respond_to?(:version) ? event_class.version : 1,
            adapters: event_class.respond_to?(:adapters) ? event_class.adapters : nil,
            timestamp: Time.now.utc,
            retention_period: event_class.respond_to?(:retention_period) ? event_class.retention_period : 30.days,
            context: {}
          }
        end

        def build_tracing_pipeline
          # Placeholder - Task 2
          ->(ed) { ed }
        end
      end
    end
  end
end
