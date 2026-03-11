# frozen_string_literal: true

# features/step_definitions/adapter_steps.rb
#
# Step definitions for adapter_configurations.feature.
# Exercises Stdout, File, Loki, and Sentry adapter configurations.

require "tempfile"
require "json"
require "stringio"

# ---------------------------------------------------------------------------
# Stdout Adapter steps
# ---------------------------------------------------------------------------

Given("a Stdout adapter with format config key {string}") do |config_str|
  config = case config_str
           when "format: :compact" then { format: :compact }
           when "pretty_print: true"  then { pretty_print: true }
           when "pretty_print: false" then { pretty_print: false }
           else raise "Unknown config string: #{config_str}"
           end
  # colorize: false avoids ANSI escape codes in captured output
  @stdout_adapter = E11y::Adapters::Stdout.new(**config, colorize: false)
end

When("I write an event through the Stdout adapter") do
  sample_event = {
    event_name: "Events::OrderCreated",
    severity: :info,
    payload: { order_id: "ord-1", status: "pending" },
    timestamp: Time.now.iso8601
  }
  @stdout_output = StringIO.new
  original_stdout = $stdout
  $stdout = @stdout_output
  begin
    @stdout_adapter.write(sample_event)
  ensure
    $stdout = original_stdout
  end
end

Then("the Stdout output should be multi-line pretty-printed JSON") do
  output = @stdout_output.string
  expect(output).to include("\n"),
                    "Expected multi-line (pretty-printed) JSON output, but got: #{output.inspect}. " \
                    "BUG: Stdout adapter uses :pretty_print key, not :format — format: :compact is silently ignored."
  parsed = begin
    JSON.parse(output)
  rescue StandardError
    nil
  end
  expect(parsed).not_to be_nil, "Output is not valid JSON: #{output.inspect}"
end

Then("the Stdout output should be a single-line JSON string") do
  output = @stdout_output.string.strip
  lines = output.split("\n").reject(&:empty?)
  expect(lines.size).to eq(1),
                        "Expected single-line compact JSON, got #{lines.size} lines:\n#{output.inspect}"
end

# ---------------------------------------------------------------------------
# File Adapter steps
# ---------------------------------------------------------------------------

Given("a File adapter writing to a temporary file") do
  @temp_file = Tempfile.new(["e11y_test", ".jsonl"])
  @file_adapter = E11y::Adapters::File.new(path: @temp_file.path)
end

When("I write a sample event through the File adapter") do
  sample_event = {
    event_name: "Events::OrderCreated",
    severity: :info,
    payload: { order_id: "ord-1", status: "pending" },
    timestamp: Time.now.iso8601
  }
  @file_adapter.write(sample_event)
end

Then("the output file should contain at least {int} valid JSON line(s)") do |min|
  @temp_file.rewind
  lines = @temp_file.readlines.map(&:strip).reject(&:empty?)
  valid = lines.select do |l|
    JSON.parse(l)
  rescue StandardError
    nil
  end
  expect(valid.size).to be >= min,
                        "Expected >= #{min} valid JSON lines in file, got #{valid.size}. Lines: #{lines.inspect}"
end

Then("the JSON line should include the field {string}") do |field|
  @temp_file.rewind
  line = @temp_file.readlines.first&.strip
  parsed = begin
    JSON.parse(line)
  rescue StandardError
    {}
  end
  expect(parsed.keys.map(&:to_s)).to include(field),
                                     "Expected JSON line to include '#{field}', got keys: #{parsed.keys.inspect}"
end

After("@adapters") do
  @temp_file&.close
  @temp_file&.unlink
end

# ---------------------------------------------------------------------------
# Loki Adapter steps
# ---------------------------------------------------------------------------

Given("a Loki adapter pointing to {string}") do |url|
  @loki_adapter = E11y::Adapters::Loki.new(url: url, timeout: 1)
end

When("I call healthy? on the Loki adapter") do
  @health_result = nil
  @health_error = nil
  begin
    @health_result = @loki_adapter.healthy?
  rescue StandardError => e
    @health_error = e
  end
end

Then("the Loki healthy? result should be false") do
  expect(@health_result).to be(false),
                            "Expected healthy? to return false for unreachable host, got: #{@health_result.inspect}. " \
                            "BUG: Loki#healthy? checks @connection.respond_to?(:get) — Faraday always responds to :get."
end

Then("calling healthy? should not raise an error") do
  expect(@health_error).to be_nil,
                         "healthy? raised: #{@health_error&.class}: #{@health_error&.message}"
  expect(@health_result).to be(true),
                           "Expected healthy? to return true when Loki is reachable, got: #{@health_result.inspect}. " \
                           "Ensure Loki is running: docker-compose up -d loki"
end

# ---------------------------------------------------------------------------
# Sentry Adapter steps
# ---------------------------------------------------------------------------

Given("Sentry SDK is initialized with a reference DSN") do
  pending "Sentry SDK not loaded — add sentry-ruby to Gemfile to test this scenario" unless defined?(Sentry)
  @reference_dsn = "https://abc123@o12345.ingest.sentry.io/99999"
  Sentry.init { |config| config.dsn = @reference_dsn }
end

When("I create an E11y Sentry adapter with a different DSN") do
  pending "Sentry SDK not loaded" unless defined?(Sentry)
  @different_dsn = "https://xyz999@other.sentry.io/11111"
  begin
    @sentry_e11y_adapter = E11y::Adapters::Sentry.new(dsn: @different_dsn)
  rescue StandardError => e
    @adapter_init_error = e
  end
end

Then("the Sentry SDK configuration should not have been overwritten") do
  pending "Sentry SDK not loaded" unless defined?(Sentry)
  current_dsn = Sentry.configuration&.dsn.to_s
  expect(current_dsn).to include("abc123"),
                         "Sentry DSN was overwritten! Expected original DSN containing 'abc123', " \
                         "but current DSN is: #{current_dsn}. " \
                         "BUG: E11y::Adapters::Sentry#initialize calls Sentry.init unconditionally, " \
                         "overwriting any existing Sentry configuration."
end
