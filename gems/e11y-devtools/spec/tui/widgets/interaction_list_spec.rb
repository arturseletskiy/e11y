# frozen_string_literal: true

require "spec_helper"
require "time"
require "e11y/devtools/tui/grouping"

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

RSpec.describe "E11y::Devtools::Tui::Widgets::InteractionList" do
  include RatatuiRuby::TestHelper if RATATUI_AVAILABLE

  before do
    skip "ratatui_ruby not available" unless RATATUI_AVAILABLE
    require "e11y/devtools/tui/widgets/interaction_list"
  end

  let(:t0) { Time.now }

  def make_interaction(trace_ids:, has_error: false)
    E11y::Devtools::Tui::Grouping::Interaction.new(
      started_at: t0,
      trace_ids: trace_ids,
      has_error?: has_error,
      source: "web"
    )
  end

  it "renders bullet as ● red when interaction has error" do
    widget = E11y::Devtools::Tui::Widgets::InteractionList.new(
      interactions: [make_interaction(trace_ids: ["t1"], has_error: true)],
      selected_index: 0
    )
    tui = RatatuiRuby::TUI.new
    with_test_terminal(40, 5) do
      expect { RatatuiRuby.draw { |frame| widget.render(tui, frame, frame.area) } }
        .not_to raise_error
      expect(buffer_content.join).to include("●")
    end
  end

  it "renders bullet as ○ when interaction is clean" do
    widget = E11y::Devtools::Tui::Widgets::InteractionList.new(
      interactions: [make_interaction(trace_ids: ["t1"], has_error: false)],
      selected_index: 0
    )
    tui = RatatuiRuby::TUI.new
    with_test_terminal(40, 5) do
      expect { RatatuiRuby.draw { |frame| widget.render(tui, frame, frame.area) } }
        .not_to raise_error
      expect(buffer_content.join).to include("○")
    end
  end
end
