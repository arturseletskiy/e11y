# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Job
        # Built-in event for failed jobs
        class Failed < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:job_class).maybe(:string)
            optional(:job_id).maybe(:string)
            optional(:queue).maybe(:string)
            optional(:error_class).maybe(:string)
            optional(:error_message).maybe(:string)
          end

          severity :error
        end
      end
    end
  end
end
