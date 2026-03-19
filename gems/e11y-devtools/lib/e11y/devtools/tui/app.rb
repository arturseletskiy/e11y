# frozen_string_literal: true

require "json"
require "pathname"
require "e11y/adapters/dev_log/query"
require_relative "grouping"

module E11y
  module Devtools
    module Tui
      # Top-level TUI application.
      #
      # Manages navigation state (:interactions | :events | :detail),
      # handles keyboard events, and reloads data when the log file changes.
      # rubocop:disable Metrics/ClassLength
      class App
        attr_reader :current_view, :source_filter

        POLL_INTERVAL_MS = 250

        def initialize(log_path: nil)
          @log_path         = log_path || auto_detect_log_path
          @query            = E11y::Adapters::DevLog::Query.new(@log_path)
          @current_view     = :interactions
          @source_filter    = :web
          @selected_ix      = 0
          @interactions     = []
          @events           = []
          @current_trace_id = nil
          @current_event    = nil
          @last_mtime       = nil
        end

        # Start the TUI event loop (blocks until user quits).
        def run
          require "ratatui_ruby"
          require_relative "widgets/interaction_list"
          require_relative "widgets/event_list"
          require_relative "widgets/event_detail"
          RatatuiRuby.run do |tui|
            loop do
              reload_if_changed!
              tui.draw { |frame| render(tui, frame) }
              event = tui.poll_event(timeout_ms: POLL_INTERVAL_MS)
              break if quit_event?(event)

              handle_key(key_from(event)) if key_event?(event)
            end
          end
        end

        # Handle a single key press (public for testability).
        def handle_key(key)
          case @current_view
          when :interactions then handle_interactions_key(key)
          when :events       then handle_events_key(key)
          when :detail       then handle_detail_key(key)
          end
        end

        # Return the currently highlighted interaction (or nil).
        def selected_interaction
          @interactions[@selected_ix]
        end

        private

        # --- Rendering ---

        def render(tui, frame)
          case @current_view
          when :interactions then render_interactions(tui, frame)
          when :events       then render_events(tui, frame)
          when :detail
            render_events(tui, frame)
            Widgets::EventDetail.new(event: @current_event).render(tui, frame, frame.area)
          end
        end

        def render_interactions(tui, frame)
          Widgets::InteractionList.new(
            interactions: @interactions,
            selected_index: @selected_ix
          ).render(tui, frame, frame.area)
        end

        def render_events(tui, frame)
          Widgets::EventList.new(
            events: @events,
            trace_id: @current_trace_id || "",
            selected_index: @selected_ix
          ).render(tui, frame, frame.area)
        end

        # --- Key handlers per view ---

        def handle_interactions_key(key)
          case key
          when "enter"  then drill_into_events
          when "j"      then @source_filter = :job
                             reload!
          when "w"      then @source_filter = :web
                             reload!
          when "a"      then @source_filter = :all
                             reload!
          when "down"   then move_down(@interactions.size)
          when "up"     then move_up
          when "r"      then reload!
          end
        end

        def handle_events_key(key)
          case key
          when "esc", "b" then back_to_interactions
          when "enter"    then drill_into_detail
          when "down"     then move_down(@events.size)
          when "up"       then move_up
          end
        end

        def handle_detail_key(key)
          case key
          when "esc", "b" then @current_view = :events
          when "c"        then copy_to_clipboard(::JSON.generate(@current_event))
          end
        end

        # --- Navigation helpers ---

        def drill_into_events
          ix = selected_interaction
          return unless ix

          @current_trace_id = ix.trace_ids.first
          @events           = @query.events_by_trace(@current_trace_id)
          @selected_ix      = 0
          @current_view     = :events
        end

        def drill_into_detail
          event = @events[@selected_ix]
          return unless event

          @current_event = event
          @current_view  = :detail
        end

        def back_to_interactions
          @current_view = :interactions
          @selected_ix  = 0
        end

        def move_down(size)
          @selected_ix = [@selected_ix + 1, size - 1].min
        end

        def move_up
          @selected_ix = [@selected_ix - 1, 0].max
        end

        # --- Data loading ---

        def reload_if_changed!
          mtime = file_mtime
          return if mtime == @last_mtime

          @last_mtime = mtime
          reload!
        end

        def reload!
          source = @source_filter == :all ? nil : @source_filter.to_s
          traces = build_traces(source)
          @interactions = Grouping.group(traces, window_ms: 500)
        end

        def build_traces(source)
          events    = @query.stored_events(limit: 5000, source: source)
          trace_map = {}
          events.each { |e| accumulate_trace(trace_map, e) }
          trace_map.values
        end

        def accumulate_trace(trace_map, event)
          tid = event["trace_id"]
          return unless tid

          entry = trace_map[tid] ||= {
            trace_id: tid,
            started_at: parse_time(event.dig("metadata", "started_at") || event["timestamp"]),
            severity: event["severity"],
            source: event.dig("metadata", "source") || "web"
          }
          entry[:severity] = "error" if %w[error fatal].include?(event["severity"])
        end

        def file_mtime
          ::File.mtime(@log_path)
        rescue Errno::ENOENT
          nil
        end

        # --- Utilities ---

        def auto_detect_log_path
          dir = Pathname.new(Dir.pwd)
          loop do
            candidate = dir.join("log", "e11y_dev.jsonl")
            return candidate.to_s if candidate.exist?

            parent = dir.parent
            break if parent == dir

            dir = parent
          end
          "log/e11y_dev.jsonl"
        end

        def parse_time(str)
          ::Time.parse(str.to_s)
        rescue ArgumentError, TypeError
          ::Time.now
        end

        def quit_event?(event)
          return false unless event
          return false unless event[:type] == :key

          event[:code] == "q" ||
            (event[:code] == "c" && event[:modifiers]&.include?("ctrl"))
        end

        def key_event?(event)
          event && event[:type] == :key
        end

        def key_from(event)
          event&.dig(:code)
        end

        def copy_to_clipboard(text)
          copy_macos(text) || copy_linux(text)
        end

        def copy_macos(text)
          ::IO.popen("pbcopy", "w") { |f| f.write(text) }
          true
        rescue StandardError
          false
        end

        def copy_linux(text)
          ::IO.popen("xclip -selection clipboard", "w") { |f| f.write(text) }
          true
        rescue StandardError
          false
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
