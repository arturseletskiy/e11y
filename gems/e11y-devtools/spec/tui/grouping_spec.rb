# frozen_string_literal: true

require "spec_helper"
require "time"
require "e11y/devtools/tui/grouping"

RSpec.describe E11y::Devtools::Tui::Grouping do
  def make_trace(id, offset_ms, severity: "info", source: "web")
    {
      trace_id:   id,
      started_at: Time.now + (offset_ms / 1000.0),
      severity:   severity,
      source:     source
    }
  end

  describe ".group" do
    it "returns empty array for empty input" do
      expect(described_class.group([])).to eq([])
    end

    it "places single trace in one interaction" do
      groups = described_class.group([make_trace("t1", 0)])
      expect(groups.size).to eq(1)
      expect(groups.first.trace_ids).to eq(["t1"])
    end

    it "groups traces within window into one interaction" do
      traces = [
        make_trace("t1", 0),
        make_trace("t2", 300),  # 300ms after t1 — within 500ms window
        make_trace("t3", 1200)  # 1200ms after t1 — outside window
      ]
      groups = described_class.group(traces, window_ms: 500)
      expect(groups.size).to eq(2)
      # newest-first: groups[0] = t3 group, groups[1] = t1+t2 group
      expect(groups.last.trace_ids.sort).to eq(%w[t1 t2].sort)
      expect(groups.first.trace_ids).to eq(["t3"])
    end

    it "marks interaction has_error? when any trace has error severity" do
      traces = [
        make_trace("t1", 0, severity: "error"),
        make_trace("t2", 100, severity: "info")
      ]
      groups = described_class.group(traces, window_ms: 500)
      expect(groups.first.has_error?).to be true
    end

    it "marks interaction clean when no errors" do
      groups = described_class.group([make_trace("t1", 0, severity: "info")])
      expect(groups.first.has_error?).to be false
    end

    it "returns groups newest-first" do
      traces = [
        make_trace("old", 0),
        make_trace("new", 2000)
      ]
      groups = described_class.group(traces, window_ms: 500)
      expect(groups.first.trace_ids).to eq(["new"])
    end
  end
end
