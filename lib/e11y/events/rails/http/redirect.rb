# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Http
        # Built-in event for redirects (redirect_to.action_controller)
        class Redirect < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:location).maybe(:string)
            optional(:status).maybe(:integer)
          end

          severity :info
        end
      end
    end
  end
end
