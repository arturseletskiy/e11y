# frozen_string_literal: true

# features/step_definitions/dlq_steps.rb
# Step definitions for dlq.feature.
# Tests DLQ::FileStorage directly (save, list, replay, delete, default path).

require "tempfile"
require "e11y/reliability/dlq/file_storage"

# ---------------------------------------------------------------------------
# Background
# ---------------------------------------------------------------------------

Given("the DLQ uses a temporary file for storage") do
  @dlq_temp = Tempfile.new(["e11y_dlq_test", ".jsonl"])
  @dlq_storage = E11y::Reliability::DLQ::FileStorage.new(file_path: @dlq_temp.path)
end

After("@dlq") do
  @dlq_temp&.close
  @dlq_temp&.unlink
end

# ---------------------------------------------------------------------------
# DLQ save steps
# ---------------------------------------------------------------------------

When("a failing adapter saves an event to the DLQ") do
  sample_event = {
    event_name: "Events::OrderCreated",
    severity: :info,
    payload: { order_id: "ord-dlq-1" },
    timestamp: Time.now.iso8601
  }
  error = StandardError.new("Simulated delivery failure")
  @dlq_entry_id = @dlq_storage.save(sample_event, metadata: { error: error })
end

# ---------------------------------------------------------------------------
# DLQ assertion steps
# ---------------------------------------------------------------------------

Then("the DLQ should contain at least {int} entry") do |min|
  entries = @dlq_storage.list
  expect(entries.size).to be >= min,
                          "Expected DLQ to contain >= #{min} entries, got #{entries.size}."
end

Then("the DLQ entry should have an event_name field") do
  entries = @dlq_storage.list
  expect(entries).not_to be_empty, "DLQ is empty — no entries found"
  entry = entries.first
  has_name = entry.key?(:event_name) || entry.key?("event_name")
  expect(has_name).to be(true),
                      "DLQ entry missing :event_name. Keys: #{entry.keys.inspect}"
end

Then("the DLQ entry should have a metadata field") do
  entries = @dlq_storage.list
  expect(entries).not_to be_empty, "DLQ is empty"
  entry = entries.first
  has_meta = entry.key?(:metadata) || entry.key?("metadata")
  expect(has_meta).to be(true),
                      "DLQ entry missing :metadata. Keys: #{entry.keys.inspect}"
end

# ---------------------------------------------------------------------------
# Replay steps (@wip — stub bug)
# ---------------------------------------------------------------------------

Given("a secondary working adapter is configured") do
  @secondary_adapter = E11y::Adapters::InMemory.new
  E11y.configuration.adapters[:secondary] = @secondary_adapter
end

When("I replay the DLQ entry") do
  @replay_result = @dlq_storage.replay(@dlq_entry_id)
end

Then("the event should appear in the secondary adapter") do
  expect(@secondary_adapter.event_count).to be >= 1,
                                            "Expected replayed event in secondary adapter, got 0. " \
                                            "BUG: DLQ#replay is a stub — E11y::Pipeline.dispatch is commented out."
end

# ---------------------------------------------------------------------------
# Delete steps (@wip — always returns false bug)
# ---------------------------------------------------------------------------

When("I delete the DLQ entry by ID") do
  @delete_result = @dlq_storage.delete(@dlq_entry_id)
end

Then("the delete result should be true") do
  expect(@delete_result).to be(true),
                            "Expected delete to return true, got #{@delete_result.inspect}. " \
                            "BUG: DLQ#delete always returns false (unimplemented TODO)."
end

# ---------------------------------------------------------------------------
# FileStorage persistence steps
# ---------------------------------------------------------------------------

Then("the DLQ file should exist on disk") do
  expect(File.exist?(@dlq_temp.path)).to be(true),
                                         "DLQ file not found at #{@dlq_temp.path}"
end

Then("the DLQ file should contain valid JSONL content") do
  lines = File.readlines(@dlq_temp.path).map(&:strip).reject(&:empty?)
  expect(lines.size).to be >= 1, "DLQ file is empty"
  lines.each_with_index do |line, i|
    parsed = begin
      JSON.parse(line)
    rescue StandardError
      nil
    end
    expect(parsed).not_to be_nil,
                          "Line #{i + 1} is not valid JSON: #{line.inspect}"
  end
end

# ---------------------------------------------------------------------------
# Default path steps (@wip — Rails.root dependency bug)
# ---------------------------------------------------------------------------

When("I create a FileStorage without an explicit path") do
  @dlq_init_error = nil
  begin
    # Hide Rails.root so we can test without Rails in scope
    E11y::Reliability::DLQ::FileStorage.new
  rescue NameError => e
    @dlq_init_error = e
  end
end

Then("no NameError should be raised") do
  expect(@dlq_init_error).to be_nil,
                             "Got NameError: #{@dlq_init_error&.message}. " \
                             "BUG: DLQ::FileStorage#default_file_path calls Rails.root — requires Rails to be loaded."
end
