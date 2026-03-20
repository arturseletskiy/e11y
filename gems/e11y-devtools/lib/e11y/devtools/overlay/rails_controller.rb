# frozen_string_literal: true

require_relative "controller"

module E11y
  module Devtools
    module Overlay
      # Thin Rails controller — delegates to plain Controller for testability.
      # Only available in development/test.
      class RailsController < ActionController::Base
        before_action :development_only!

        def events
          render json: overlay_ctrl.events_for(trace_id: params[:trace_id])
        end

        def recent
          render json: overlay_ctrl.recent_events(limit: params[:limit])
        end

        def clear
          overlay_ctrl.clear_log!
          head :no_content
        end

        def stats
          render json: overlay_ctrl.stats
        end

        def overlay_js
          path = E11y::Devtools::Overlay::Engine.root.join(
            "lib/e11y/devtools/overlay/assets/overlay.js"
          )
          return head :not_found unless path.file?

          send_file path, type: "application/javascript", disposition: "inline"
        end

        def v1_interactions
          render json: overlay_ctrl.v1_interactions(
            source: params[:source],
            limit: params[:limit],
            window_ms: params[:window_ms]
          )
        end

        def v1_trace_events
          render json: overlay_ctrl.v1_trace_events(params[:trace_id])
        end

        def v1_events_recent
          render json: overlay_ctrl.v1_recent_events(limit: params[:limit])
        end

        private

        def overlay_ctrl
          @overlay_ctrl ||= Controller.new
        end

        def development_only!
          head :not_found unless Rails.env.development? || Rails.env.test?
        end
      end
    end
  end
end
