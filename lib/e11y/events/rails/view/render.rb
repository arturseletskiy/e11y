# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module View
        # Built-in event for view rendering (render_template.action_view)
        class Render < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:identifier).maybe(:string)
            optional(:layout).maybe(:string)
            optional(:allocations).maybe(:integer)
          end

          severity :debug
          sample_rate 0.1 # Sample view renders at 10%
        end
      end
    end
  end
end
