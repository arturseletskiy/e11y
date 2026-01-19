# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Job
        # Built-in event for started jobs (perform_start.active_job)
        class Started < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:job_class).maybe(:string)
            optional(:job_id).maybe(:string)
            optional(:queue).maybe(:string)
          end

          severity :info
        end
      end
    end
  end
end
