# frozen_string_literal: true

require "spec_helper"
require "time"
require "e11y/devtools/tui/grouping"

RSpec.describe "E11y::Devtools::Tui::Widgets::InteractionList" do
  before do
    skip "ratatui_ruby not available" unless defined?(RatatuiRuby)
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
    with_test_terminal(40, 5) do |terminal|
      terminal.draw { |frame| frame.render_widget(widget, frame.area) }
      assert_cell_style(0, 1, char: "●", fg: :red)
    end
  end

  it "renders bullet as ○ when interaction is clean" do
    widget = E11y::Devtools::Tui::Widgets::InteractionList.new(
      interactions: [make_interaction(trace_ids: ["t1"], has_error: false)],
      selected_index: 0
    )
    with_test_terminal(40, 5) do |terminal|
      terminal.draw { |frame| frame.render_widget(widget, frame.area) }
      assert_cell_style(0, 1, char: "○")
    end
  end
end
