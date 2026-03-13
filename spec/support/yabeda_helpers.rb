# frozen_string_literal: true

# Shared Yabeda helpers for integration specs.
#
# **Unified approach:**
# - NEVER call Yabeda.reset! in integration specs — it destroys the e11y group and breaks subsequent specs
# - Register metrics via register_yabeda_metric_if_needed (only if not already registered)
# - Reset only metric VALUES between tests via reset_yabeda_values! (clears @values, keeps definitions)
#
# @see spec/integration/pattern_metrics_integration_spec.rb
# @see spec/integration/slo_tracking_integration_spec.rb
# @see spec/integration/high_cardinality_protection_integration_spec.rb
module YabedaHelpers
  # Register a Yabeda metric only if it doesn't already exist.
  # Use this instead of Yabeda.configure + configure! to avoid AlreadyConfiguredError.
  #
  # @param type [Symbol] :counter, :histogram, or :gauge
  # @param name [Symbol] Metric name (e.g. :orders_total)
  # @param options [Hash] Tags, buckets, comment
  # @return [void]
  def register_yabeda_metric_if_needed(type, name, **options)
    return unless defined?(Yabeda)

    metric_key = "e11y_#{name}"
    return if Yabeda.metrics.key?(metric_key)

    Yabeda.configure do
      group :e11y do
        case type
        when :counter
          counter name, **options
        when :histogram
          histogram name, **options
        when :gauge
          gauge name, **options
        end
      end
    end
  end

  # Reset Yabeda metric values (not definitions).
  # Clears @values on each metric so tests don't accumulate state.
  # Does NOT call Yabeda.reset! — that would destroy the e11y group.
  #
  # @return [void]
  def reset_yabeda_values!
    return unless defined?(Yabeda) && Yabeda.configured?

    Yabeda.metrics.each do |metric_name, metric|
      next unless metric_name.to_s.start_with?("e11y_")

      values = metric.instance_variable_get(:@values)
      values&.clear if values.respond_to?(:clear)
    end
  rescue StandardError => e
    warn "Could not reset Yabeda values: #{e.message}"
  end
end

RSpec.configure do |config|
  config.include YabedaHelpers
end
