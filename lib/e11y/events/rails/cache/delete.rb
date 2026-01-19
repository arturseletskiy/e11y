# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Cache
        # Built-in event for cache deletes (cache_delete.active_support)
        class Delete < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:key).maybe(:string)
          end

          severity :debug
          sample_rate 0.1 # Sample cache deletes at 10%
        end
      end
    end
  end
end
