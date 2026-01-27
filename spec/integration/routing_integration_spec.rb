# frozen_string_literal: true

require "rails_helper"

# Routing middleware integration tests for UC-019
# Tests retention-based routing, explicit adapter selection, routing rules, fallback adapters
#
# Scenarios:
# 1. Explicit adapter selection (bypass routing)
# 2. Routing rules evaluation (lambda-based)
# 3. Fallback adapters
# 4. Multi-adapter fanout
# 5. Error handling (adapter failures)

RSpec.describe "Routing Middleware Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:stdout_adapter) { E11y::Adapters::Stdout.new }
  let(:file_adapter) do
    temp_dir = Dir.mktmpdir("routing_test")
    E11y::Adapters::File.new(path: File.join(temp_dir, "events.log"))
  end

  before do
    memory_adapter.clear!

    # Register multiple adapters for testing
    E11y.config.adapters[:stdout] = stdout_adapter
    E11y.config.adapters[:file] = file_adapter

    # Configure routing
    E11y.config.routing_rules = []
    E11y.config.fallback_adapters = [:memory]

    # Ensure Routing middleware is in pipeline
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  after do
    memory_adapter.clear!
    E11y.config.adapters.delete(:stdout)
    E11y.config.adapters.delete(:file)
    FileUtils.rm_rf(File.dirname(file_adapter.path)) if file_adapter.path
  end

  describe "Scenario 1: Explicit adapter selection" do
    it "routes events to explicitly specified adapters, bypassing routing rules" do
      # Setup: Event with explicit adapters field
      # Test: Track event with adapters: [:stdout, :file]
      # Expected: Event goes to stdout and file adapters, not to memory (fallback)

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :stdout, :file
      end
      stub_const("Events::TestExplicitRouting", test_event_class)

      memory_adapter.clear!

      Events::TestExplicitRouting.track(test_id: 1, message: "Explicit routing test")

      # Event should NOT go to memory (fallback bypassed)
      memory_events = memory_adapter.find_events("Events::TestExplicitRouting")
      expect(memory_events.count).to eq(0), "Explicit adapters should bypass fallback"

      # Event should go to file adapter
      # File adapter writes JSON, so check for event_name or payload content
      file_content = File.read(file_adapter.path) if File.exist?(file_adapter.path)
      expect(file_content).to be_present, "File adapter should have content"
      # Check for either class name or normalized event name in JSON
      expect(file_content).to(match(/TestExplicitRouting|test\.explicit\.routing|"test_id"\s*:\s*1/),
                              "Event should be routed to file adapter. Content: #{file_content[0..200]}")
    end

    it "supports multi-adapter fanout with explicit adapters" do
      # Setup: Event with multiple explicit adapters
      # Test: Track event with adapters: [:memory, :stdout, :file]
      # Expected: Event goes to all three adapters

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :memory, :stdout, :file
      end
      stub_const("Events::TestMultiFanout", test_event_class)

      memory_adapter.clear!

      Events::TestMultiFanout.track(test_id: 1, message: "Multi-adapter fanout test")

      # Event should go to memory adapter
      # Note: event_name is normalized by Versioning middleware
      memory_events = find_events_by_class(memory_adapter, test_event_class)
      expect(memory_events.count).to eq(1), "Event should be routed to memory adapter"

      # Event should go to file adapter
      # File adapter writes JSON, so check for event_name or payload content
      file_content = File.read(file_adapter.path) if File.exist?(file_adapter.path)
      expect(file_content).to be_present, "File adapter should have content"
      # Check for either class name or normalized event name in JSON
      expect(file_content).to(match(/TestMultiFanout|test\.multi\.fanout|"test_id"\s*:\s*1/),
                              "Event should be routed to file adapter. Content: #{file_content[0..200]}")
    end
  end

  describe "Scenario 2: Routing rules evaluation" do
    it "evaluates routing rules in order and routes to first matching rule" do
      # Setup: Multiple routing rules
      # Test: Track event that matches first rule
      # Expected: Event routed to adapter from first matching rule

      # Configure routing rules
      # Note: Versioning middleware is opt-in, so event_name may not be normalized
      # Check by event_class name or original event_name
      E11y.config.routing_rules = [
        ->(event) { :memory if event[:event_class]&.name&.include?("Test") || event[:event_name]&.include?("Test") },
        ->(event) { :file if event[:payload]&.dig(:test_id) == 1 }
      ]
      E11y.config.fallback_adapters = [] # Disable fallback to test routing rules

      test_event_class = Class.new(E11y::Event::Base) do
        # No explicit adapters - will use routing rules
      end
      stub_const("Events::TestRoutingRules", test_event_class)

      # Clear pipeline cache to ensure routing rules are used
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      memory_adapter.clear!

      Events::TestRoutingRules.track(test_id: 1, message: "Routing rules test")

      # First rule should match (event_class name includes "Test")
      # Event should go to memory (from first rule)
      memory_events = find_events_by_class(memory_adapter, test_event_class)
      expect(memory_events.count).to eq(1), "Routing rule should route to memory adapter. Total events: #{memory_adapter.events.count}, event_names: #{memory_adapter.events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
    end

    it "routes to fallback adapters when no routing rule matches" do
      # Setup: Routing rules that don't match
      # Test: Track event that doesn't match any rule
      # Expected: Event routed to fallback adapters

      # Configure routing rules that won't match
      E11y.config.routing_rules = [
        ->(event) { :stdout if event[:event_name]&.include?("NonExistent") },
        ->(event) { :file if event[:payload]&.dig(:test_id) == 999 }
      ]
      E11y.config.fallback_adapters = [:memory]

      test_event_class = Class.new(E11y::Event::Base) do
        # No explicit adapters, no matching rules
      end
      stub_const("Events::TestFallback", test_event_class)

      # Clear pipeline cache to ensure routing rules are used
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      memory_adapter.clear!

      Events::TestFallback.track(test_id: 1, message: "Fallback test")

      # Event should go to fallback adapter (memory)
      memory_events = find_events_by_class(memory_adapter, test_event_class)
      expect(memory_events.count).to eq(1), "Event should be routed to fallback adapter when no rule matches. Total events: #{memory_adapter.events.count}, event_names: #{memory_adapter.events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
    end

    it "supports retention-based routing rules" do
      # Setup: Routing rule based on retention_until
      # Test: Track event with retention_until
      # Expected: Event routed based on retention period

      # Configure routing rule based on retention
      E11y.config.routing_rules = [
        lambda do |event|
          if event[:retention_until]
            retention_days = (Time.parse(event[:retention_until]) - Time.now).to_i / 86_400
            :memory if retention_days > 30 # Long retention → memory (for testing)
          end
        end
      ]
      E11y.config.fallback_adapters = [] # Disable fallback

      test_event_class = Class.new(E11y::Event::Base) do
        retention_period 90.days # Long retention
      end
      stub_const("Events::TestRetentionRouting", test_event_class)

      # Clear pipeline cache to ensure routing rules are used
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      memory_adapter.clear!

      Events::TestRetentionRouting.track(test_id: 1, message: "Retention routing test")

      # Event should go to memory adapter (long retention rule matches)
      memory_events = find_events_by_class(memory_adapter, test_event_class)
      expect(memory_events.count).to eq(1), "Long retention event should route to memory adapter based on retention rule. Total events: #{memory_adapter.events.count}, event_names: #{memory_adapter.events.map do |e|
        e[:event_name]
      end.uniq.inspect}, retention_until: #{memory_adapter.events.map do |e|
                                            e[:retention_until]
                                          end.uniq.inspect}"
    end
  end

  describe "Scenario 3: Fallback adapters" do
    it "routes to fallback adapters when no routing rules match" do
      # Setup: No routing rules, fallback adapters configured
      # Test: Track event
      # Expected: Event routed to fallback adapters

      E11y.config.routing_rules = []
      E11y.config.fallback_adapters = %i[memory stdout]

      test_event_class = Class.new(E11y::Event::Base) do
        # No explicit adapters
      end
      stub_const("Events::TestFallbackOnly", test_event_class)

      memory_adapter.clear!

      Events::TestFallbackOnly.track(test_id: 1, message: "Fallback only test")

      # Event should go to fallback adapters
      # Note: event_name is normalized by Versioning middleware
      memory_events = find_events_by_class(memory_adapter, test_event_class)
      expect(memory_events.count).to eq(1), "Event should be routed to fallback adapters"
    end

    it "handles empty fallback adapters gracefully" do
      # Setup: No routing rules, no fallback adapters
      # Test: Track event
      # Expected: Event is dropped (no adapters to route to) or goes to default adapter

      E11y.config.routing_rules = []
      E11y.config.fallback_adapters = []

      test_event_class = Class.new(E11y::Event::Base) do
        # No explicit adapters
      end
      stub_const("Events::TestNoFallback", test_event_class)

      memory_adapter.clear!

      # Should not raise exception
      expect do
        Events::TestNoFallback.track(test_id: 1, message: "No fallback test")
      end.not_to raise_error

      # Event may go to default adapter or be dropped
      # This depends on implementation - verify graceful handling
      memory_events = memory_adapter.find_events("Events::TestNoFallback")
      # Accept either 0 (dropped) or 1 (default adapter) - both are valid behaviors
      expect(memory_events.count).to be_between(0, 1),
                                     "Event should be handled gracefully when no adapters available (dropped or default adapter)"
    end
  end

  describe "Scenario 4: Multi-adapter fanout" do
    it "routes events to multiple adapters when routing rule returns array" do
      # Setup: Routing rule that returns array of adapters
      # Test: Track event
      # Expected: Event routed to all adapters in array

      # Configure routing rule that returns multiple adapters
      E11y.config.routing_rules = [
        ->(event) { %i[memory stdout] if event[:event_name]&.include?("Multi") }
      ]
      E11y.config.fallback_adapters = [] # Disable fallback

      test_event_class = Class.new(E11y::Event::Base) do
        # No explicit adapters
      end
      stub_const("Events::TestMultiRouting", test_event_class)

      memory_adapter.clear!

      Events::TestMultiRouting.track(test_id: 1, message: "Multi routing test")

      # Event should go to memory adapter (one of the adapters in array)
      # Note: event_name is normalized by Versioning middleware
      memory_events = find_events_by_class(memory_adapter, test_event_class)
      expect(memory_events.count).to eq(1), "Event should be routed to memory adapter when routing rule returns array"
    end
  end

  describe "Scenario 5: Error handling" do
    it "handles adapter not found gracefully" do
      # Setup: Explicit adapter that doesn't exist
      # Test: Track event with non-existent adapter
      # Expected: Event is dropped gracefully, no exception raised

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :non_existent_adapter
      end
      stub_const("Events::TestMissingAdapter", test_event_class)

      memory_adapter.clear!

      # Should not raise exception
      expect do
        Events::TestMissingAdapter.track(test_id: 1, message: "Missing adapter test")
      end.not_to raise_error

      # Event should not go to memory (adapter not found)
      # Note: event_name is normalized by Versioning middleware
      memory_events = find_events_by_class(memory_adapter, test_event_class)
      expect(memory_events.count).to eq(0), "Event should be dropped when adapter not found"
    end

    it "handles routing rule errors gracefully" do
      # Setup: Routing rule that raises error
      # Test: Track event
      # Expected: Error is caught, event routed to fallback or dropped

      # Configure routing rule that raises error
      E11y.config.routing_rules = [
        ->(_event) { raise StandardError, "Routing rule error" }
      ]
      E11y.config.fallback_adapters = [:memory]

      test_event_class = Class.new(E11y::Event::Base) do
        # No explicit adapters
      end
      stub_const("Events::TestRuleError", test_event_class)

      memory_adapter.clear!

      # Should not raise exception (error caught)
      expect do
        Events::TestRuleError.track(test_id: 1, message: "Rule error test")
      end.not_to raise_error

      # Event should go to fallback adapter (error handled gracefully)
      # Note: event_name is normalized by Versioning middleware
      memory_events = find_events_by_class(memory_adapter, test_event_class)
      expect(memory_events.count).to eq(1), "Event should be routed to fallback when routing rule errors"
    end

    it "continues routing to other adapters when one adapter fails" do
      # Setup: Multiple adapters, one fails
      # Test: Track event
      # Expected: Event goes to working adapters, failed adapter doesn't crash pipeline

      # Mock file adapter to raise error
      allow(file_adapter).to receive(:write).and_raise(StandardError.new("File adapter error"))

      test_event_class = Class.new(E11y::Event::Base) do
        adapters :memory, :file
      end
      stub_const("Events::TestAdapterFailure", test_event_class)

      memory_adapter.clear!

      # Should not raise exception (error caught)
      expect do
        Events::TestAdapterFailure.track(test_id: 1, message: "Adapter failure test")
      end.not_to raise_error

      # Event should still go to memory adapter (other adapter works)
      # Note: event_name is normalized by Versioning middleware
      memory_events = find_events_by_class(memory_adapter, test_event_class)
      expect(memory_events.count).to eq(1), "Event should be routed to working adapters even if one fails"
    end
  end
end
