# frozen_string_literal: true

require "spec_helper"
require "time"

unless defined?(RATATUI_AVAILABLE)
  begin
    require "minitest"
    require "ratatui_ruby"
    require "ratatui_ruby/test_helper"
    RATATUI_AVAILABLE = true
  rescue LoadError
    RATATUI_AVAILABLE = false
  end
end

RSpec.describe "E11y::Devtools::Tui::Widgets::EventList" do
  include RatatuiRuby::TestHelper if RATATUI_AVAILABLE

  before do
    skip "ratatui_ruby not available" unless RATATUI_AVAILABLE
    require "e11y/devtools/tui/widgets/event_list"
  end

  let(:events) do
    [
      { "severity" => "error", "event_name" => "order.failed",
        "timestamp" => Time.now.iso8601, "metadata" => {} },
      { "severity" => "info", "event_name" => "order.created",
        "timestamp" => Time.now.iso8601, "metadata" => { "duration_ms" => 42 } }
    ]
  end

  it "renders without raising" do
    widget = E11y::Devtools::Tui::Widgets::EventList.new(
      events: events, trace_id: "trace-1", selected_index: 0
    )
    tui = RatatuiRuby::TUI.new
    with_test_terminal(80, 10) do
      expect { RatatuiRuby.draw { |frame| widget.render(tui, frame, frame.area) } }
        .not_to raise_error
    end
  end
end
