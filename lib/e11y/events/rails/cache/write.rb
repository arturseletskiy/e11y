# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Cache
        # Built-in event for cache writes (cache_write.active_support)
        class Write < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:key).maybe(:string)
            optional(:super_operation).maybe(:string)
          end

          severity :debug
          sample_rate 0.01 # Sample cache writes at 1%
        end
      end
    end
  end
end
