# frozen_string_literal: true

module E11y
  module TraceContext
    # Trace entry sampler (ADR-005 §7).
    # Decides if trace should be sampled; respects parent decision when configured.
    class Sampler
      class << self
        def should_sample?(context = {})
          cfg = E11y.config&.tracing
          respect = cfg&.respect_parent_sampling != false

          return context[:sampled] if respect && context.key?(:sampled)

          rate = determine_sample_rate(context, cfg)
          rand < rate
        end

        private

        def determine_sample_rate(context, cfg)
          return 1.0 if context[:error]
          return 1.0 if cfg&.always_sample_if&.call(context)

          if context[:event_name] && cfg&.per_event_sample_rates
            rate = cfg.per_event_sample_rates[context[:event_name].to_s]
            return rate if rate
          end

          (cfg&.default_sample_rate || 0.1).to_f
        end
      end
    end
  end
end
