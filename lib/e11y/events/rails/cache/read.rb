# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Cache
        # Built-in event for cache reads (cache_read.active_support)
        class Read < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:key).maybe(:string)
            optional(:hit).maybe(:bool)
            optional(:super_operation).maybe(:string)
          end

          severity :debug
          sample_rate 0.01 # Sample cache reads at 1% (very high volume)
        end
      end
    end
  end
end
