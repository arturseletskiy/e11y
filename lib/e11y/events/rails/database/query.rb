# frozen_string_literal: true

module E11y
  module Events
    module Rails
      module Database
        # Built-in event for SQL queries (sql.active_record)
        #
        # Tracks database queries from ActiveRecord with timing and connection info.
        #
        # @example Usage (automatic via Rails Instrumentation)
        #   # Automatically tracked when Rails executes SQL:
        #   User.where(email: 'user@example.com').first
        #   # → Events::Rails::Database::Query tracked
        #
        # @example Custom override
        #   # config/initializers/e11y.rb
        #   E11y.configure do |config|
        #     config.rails_instrumentation_custom_mappings['sql.active_record'] = MyApp::CustomDatabaseQuery
        #   end
        #
        # @see ADR-008 §4.3 (Built-in Event Classes)
        class Query < E11y::Event::Base
          schema do
            required(:event_name).filled(:string)
            required(:duration).filled(:float)
            optional(:name).maybe(:string)
            optional(:sql).maybe(:string)
            optional(:connection_id).maybe(:integer)
            optional(:binds).maybe(:array)
            optional(:allocations).maybe(:integer)
          end

          severity :debug # SQL queries are debug-level by default

          # Sample SQL queries at 10% (can be overridden)
          sample_rate 0.1
        end
      end
    end
  end
end
