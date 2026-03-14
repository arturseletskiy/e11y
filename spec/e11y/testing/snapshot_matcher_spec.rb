# frozen_string_literal: true

RSpec.describe E11y::Testing::SnapshotMatcher do
  let(:snapshot_path) { "spec/snapshots/events/test_event.yml" }

  around do |example|
    FileUtils.rm_f(snapshot_path)
    example.run
  ensure
    FileUtils.rm_f(snapshot_path)
  end

  it "creates snapshot on first run and matches on subsequent run" do
    event = {
      payload: { order_id: 123 },
      event_name: "order.created",
      severity: :info,
      timestamp: "2026-01-01T12:00:00.000Z",
      trace_id: "abc123",
      span_id: "def456"
    }

    expect(event).to match_snapshot("test_event")
    expect(File).to exist(snapshot_path)

    # Same event (different volatile values) should still match after normalization
    event2 = event.merge(timestamp: "2026-01-02T00:00:00.000Z", trace_id: "xyz", span_id: "789")
    expect(event2).to match_snapshot("test_event")
  end

  it "fails when event differs from snapshot" do
    event = { payload: { order_id: 123 }, event_name: "order.created" }
    expect(event).to match_snapshot("test_event")

    different_event = { payload: { order_id: 456 }, event_name: "order.created" }
    expect(different_event).not_to match_snapshot("test_event")
  end

  it "updates snapshot when UPDATE_SNAPSHOTS=1" do
    ClimateControl.modify(UPDATE_SNAPSHOTS: "1") do
      event = { payload: { id: 1 }, event_name: "test" }
      expect(event).to match_snapshot("test_event")
    end
    expect(File).to exist(snapshot_path)
  end
end
