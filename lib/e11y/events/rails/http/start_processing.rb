# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Http
        # Event for `start_processing.action_controller` ASN notification
        #
        # Fired when Rails starts processing a controller action.
        #
        # @see https://guides.rubyonrails.org/active_support_instrumentation.html#start-processing-action-controller
        class StartProcessing < E11y::Event::Base
          schema do
            required(:controller).filled(:string)
            required(:action).filled(:string)
            required(:method).filled(:string)
            required(:path).filled(:string)
            required(:format).filled(:string)
          end

          severity :debug
        end
      end
    end
  end
end
