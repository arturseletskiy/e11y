# frozen_string_literal: true

# Temporary debug helper for pipeline state inspection
module PipelineDebug
  def self.log(message, data = {})
    return unless ENV["E11Y_DEBUG_PIPELINE"]

    puts "\n[PIPELINE DEBUG] #{message}"
    data.each do |key, value|
      puts "  #{key}: #{value.inspect}"
    end
  end

  def self.inspect_adapters
    log("Adapter state", {
          configured: E11y.configuration.adapters.keys,
          count: E11y.configuration.adapters.size
        })
  end

  def self.inspect_pipeline
    log("Pipeline state", {
          built: E11y.configuration.instance_variable_get(:@built_pipeline) ? "yes" : "no",
          middlewares: E11y.configuration.pipeline.middlewares.map(&:to_s)
        })
  end
end

# Patch E11y::Middleware::Routing for debugging
module E11y
  module Middleware
    class Routing
      alias original_call call

      def call(event_data)
        if ENV["E11Y_DEBUG_PIPELINE"]
          PipelineDebug.log("Routing middleware called", {
                              event_name: event_data[:event_name],
                              explicit_adapters: event_data[:adapters],
                              configured_adapters: E11y.configuration.adapters.keys
                            })
        end

        result = original_call(event_data)

        if ENV["E11Y_DEBUG_PIPELINE"] && result
          PipelineDebug.log("Routing result", {
                              routed_to: result[:routing][:adapters],
                              routing_type: result[:routing][:routing_type]
                            })
        end

        result
      end
    end
  end
end
