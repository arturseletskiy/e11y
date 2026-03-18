# frozen_string_literal: true

require "spec_helper"

RSpec.describe "E11y Memory Profile", :memory do # rubocop:disable RSpec/DescribeClass
  # Anonymous event classes — no Rails, no adapters, no Docker.
  # Defined as let-blocks to avoid cross-example state from class definitions.

  let(:payload) { { value: 42 } }

  # Fix trace_id so the Sampling middleware reuses one cached decision per test
  # instead of allocating a new String key per event.  Without this, each
  # Event.track generates a unique trace_id → one new @trace_decisions entry →
  # MemoryProfiler counts it as retained (the cache is bounded to 1000, so it
  # is NOT a real production leak, but it pollutes the measurement).
  before do
    Thread.current[:e11y_trace_id] = "memory-test-fixed-trace-id"
  end

  after do
    Thread.current[:e11y_trace_id] = nil
  end

  # Prints allocation metrics to stdout on every run (even green) for observability.
  def print_allocation_summary(report, label:, event_count:)
    per_event = (report.total_allocated.to_f / event_count).round(2)
    puts "\n  [Memory] #{label}:"
    puts "     allocated: #{report.total_allocated} objects (#{per_event}/event)"
    puts "     retained:  #{report.total_retained} objects"
    puts "     memory:    #{(report.total_allocated_memsize / 1024.0).round(2)} KB"
  end

  # -------------------------------------------------------------------------
  # Group 1: Event.track allocations by validation_mode
  # -------------------------------------------------------------------------
  describe "Event.track allocations" do
    context "with validation_mode :always (default)" do
      let(:event_class) do
        Class.new(E11y::Event::Base) do
          def self.name = "MemoryTestAlwaysEvent"
          contains_pii false # force no_pii — no Rails filter in unit context
          schema { required(:value).filled(:integer) }
        end
      end

      it "allocates <=90 objects per event and retains 0" do
        report = measure_allocations(count: 100) { event_class.track(**payload) }
        per_event = report.total_allocated.to_f / 100
        print_allocation_summary(report, label: "validation_mode :always", event_count: 100)

        aggregate_failures do
          # Strict: retained > 0 means a real memory leak — must fix, not tune threshold.
          expect(report.total_retained).to eq(0),
                                           "Memory leak: #{report.total_retained} objects retained after 100 events"

          # Soft: baseline ~47/event on Ruby 3.3, ~80/event on Ruby 3.2 + Rails 8.0
          # (Rails 8.0 / Ruby 3.2 combination allocates more in dry-schema path).
          # Threshold = ceil(80 * 1.1) = 88, rounded to 90 for cross-version buffer.
          # See benchmarks/allocation_profiling.rb.
          expect(per_event).to be <= 90,
                               "Allocation regression: #{per_event.round(2)} objects/event exceeds <=90 target. " \
                               "Run benchmarks/allocation_profiling.rb for detailed source analysis."
        end
      end
    end

    context "with validation_mode :never" do
      let(:event_class_never) do
        Class.new(E11y::Event::Base) do
          def self.name = "MemoryTestNeverEvent"
          contains_pii false
          validation_mode :never
          schema { required(:value).filled(:integer) }
        end
      end

      it "allocates <=50 objects per event and retains 0" do
        report = measure_allocations(count: 100) { event_class_never.track(**payload) }
        per_event = report.total_allocated.to_f / 100
        print_allocation_summary(report, label: "validation_mode :never", event_count: 100)

        aggregate_failures do
          expect(report.total_retained).to eq(0),
                                           "Memory leak: #{report.total_retained} objects retained after 100 events"

          # Measured baseline: ~33/event on Ruby 3.3 (pipeline overhead without dry-schema).
          # Threshold = ceil(33 * 1.6) = 53. See benchmarks/allocation_profiling.rb.
          expect(per_event).to be <= 55,
                               "Allocation regression: #{per_event.round(2)} objects/event exceeds <=55 target " \
                               "for :never mode. See benchmarks/allocation_profiling.rb."
        end
      end
    end

    context "with validation_mode :sampled (50%)" do
      let(:event_class_sampled) do
        Class.new(E11y::Event::Base) do
          def self.name = "MemoryTestSampledEvent"
          contains_pii false
          # 50% rate ensures dry-schema is compiled in warmup (1-(0.5^10) ≈ 99.9%).
          # Lower rates (e.g. 1%) make schema compilation probabilistic, causing
          # non-deterministic retained-object counts from class-level caching.
          validation_mode :sampled, sample_rate: 0.5
          schema { required(:value).filled(:integer) }
        end
      end

      it "allocates <=72 objects per event and retains 0" do
        report = measure_allocations(count: 100) { event_class_sampled.track(**payload) }
        per_event = report.total_allocated.to_f / 100
        print_allocation_summary(report, label: "validation_mode :sampled (50%)", event_count: 100)

        aggregate_failures do
          expect(report.total_retained).to eq(0),
                                           "Memory leak: #{report.total_retained} objects retained after 100 events"

          # Measured baseline: ~33–47/event on Ruby 3.3 (50% validates → midpoint).
          # Upper bound matches :always threshold (ceil(47 * 1.5) = 72).
          expect(per_event).to be <= 72,
                               "Allocation regression: #{per_event.round(2)} objects/event exceeds <=72 target."
        end
      end
    end
  end

  # -------------------------------------------------------------------------
  # Group 2: Leak detection at scale
  # Uses :never mode to isolate pipeline allocations from dry-schema overhead.
  # -------------------------------------------------------------------------
  describe "Memory leaks at scale" do
    let(:leak_test_class) do
      Class.new(E11y::Event::Base) do
        def self.name = "MemoryLeakTestEvent"
        contains_pii false
        validation_mode :never
        schema { required(:value).filled(:integer) }
      end
    end

    def leak_detail(report)
      return "" if report.total_retained.zero?

      # retained_memory_by_class returns [{data: ClassName, count: N}, ...]
      top = report.retained_memory_by_class.first(5)
                  .map { |entry| "  #{entry[:data]}: #{entry[:count]} objects" }
                  .join("\n")
      "\nTop retained classes:\n#{top}"
    end

    it "retains 0 objects after 1K events" do
      report = measure_allocations(count: 1_000, warmup: 20) { leak_test_class.track(**payload) }
      print_allocation_summary(report, label: "1K events leak check", event_count: 1_000)

      expect(report.total_retained).to eq(0),
                                       "Memory leak at 1K events: #{report.total_retained} objects retained.#{leak_detail(report)}"
    end

    it "retains 0 objects after 10K events" do
      report = measure_allocations(count: 10_000, warmup: 50) { leak_test_class.track(**payload) }
      print_allocation_summary(report, label: "10K events leak check", event_count: 10_000)

      expect(report.total_retained).to eq(0),
                                       "Memory leak at 10K events: #{report.total_retained} objects retained.#{leak_detail(report)}"
    end
  end

  # -------------------------------------------------------------------------
  # Group 3: Memory consumption (Small Scale target from benchmarks/README.md)
  # -------------------------------------------------------------------------
  describe "Memory consumption" do
    let(:event_class) do
      Class.new(E11y::Event::Base) do
        def self.name = "MemoryConsumptionEvent"
        contains_pii false
        schema { required(:value).filled(:integer) }
      end
    end

    it "allocates <100MB for 1K events (Small Scale target)" do
      report = measure_allocations(count: 1_000, warmup: 10) { event_class.track(**payload) }
      allocated_mb = report.total_allocated_memsize.to_f / (1024 * 1024)

      puts "\n  [Memory] consumption (1K events):"
      puts "     allocated: #{allocated_mb.round(3)} MB"
      puts "     target:    < 100 MB  (benchmarks/README.md Small Scale)"

      expect(allocated_mb).to be < 100,
                              "Memory consumption #{allocated_mb.round(2)} MB exceeds 100 MB target " \
                              "(benchmarks/README.md Small Scale: track() latency <50us, memory <100MB)."
    end
  end
end
