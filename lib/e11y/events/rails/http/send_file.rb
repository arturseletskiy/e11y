# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Http
        # Built-in event for file sending (send_file.action_controller)
        class SendFile < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:path).maybe(:string)
            optional(:filename).maybe(:string)
          end

          severity :info
        end
      end
    end
  end
end
