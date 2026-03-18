# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe "E11y::Devtools::Tui::Widgets::EventList" do
  before do
    skip "ratatui_ruby not available" unless defined?(RatatuiRuby)
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
    with_test_terminal(80, 10) do |terminal|
      expect { terminal.draw { |frame| frame.render_widget(widget, frame.area) } }
        .not_to raise_error
    end
  end
end
