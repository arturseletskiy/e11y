# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Http
        # Built-in event for HTTP requests (process_action.action_controller)
        class Request < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:controller).maybe(:string)
            optional(:action).maybe(:string)
            optional(:format).maybe(:string)
            optional(:status).maybe(:integer)
            optional(:view_runtime).maybe(:float)
            optional(:db_runtime).maybe(:float)
            optional(:allocations).maybe(:integer)
          end

          severity :info
        end
      end
    end
  end
end
