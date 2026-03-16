# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module E11y
  module Debug
    # Debug utility to trace events through the pipeline with per-middleware logging.
    class PipelineInspector
      # Wraps a middleware to log enter/exit for pipeline tracing.
      class TracingWrapper
        def initialize(middleware_class, next_app, name, args: [], options: {})
          @middleware_class = middleware_class
          @next_app = next_app
          @name = name
          @args = args
          @options = options
        end

        def call(event_data)
          log_enter(@name)
          result = @middleware_class.new(@next_app, *@args, **@options).call(event_data)
          log_exit(@name)
          result
        end

        private

        def log_enter(name)
          prefix = $stdout.tty? ? "\e[33m" : ""
          suffix = $stdout.tty? ? "\e[0m" : ""
          print "  #{prefix}#{name}#{suffix}... "
        end

        def log_exit(_name)
          mark = $stdout.tty? ? "\e[32m✓\e[0m" : "✓"
          puts mark
        end
      end

      class << self
        def trace_event(event_class, **payload)
          event_name = event_class.respond_to?(:event_name) ? event_class.event_name : event_class.name
          puts "\n🔍 Tracing Event Pipeline: #{event_name}\n\n"
          event_data = build_event_data(event_class, payload)
          pipeline = build_tracing_pipeline
          result = pipeline.call(event_data)
          puts "\n✅ Pipeline trace complete\n"
          result
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
          builder = E11y.configuration.pipeline
          final_app = ->(event_data) { event_data }

          builder.middlewares.reverse.reduce(final_app) do |next_app, entry|
            name = entry.middleware_class.name.split("::").last
            TracingWrapper.new(
              entry.middleware_class,
              next_app,
              name,
              args: entry.args,
              options: entry.options
            )
          end
        end
      end
    end
  end
end
