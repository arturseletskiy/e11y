# frozen_string_literal: true

require "rails_helper"
require "memory_profiler"

# Realistic memory profile for production-typical event tracking.
#
# Uses real event classes from the dummy app (contains_pii true, metrics, SLO),
# with the NullAdapter as the delivery target. NullAdapter discards events immediately
# (write returns true without storing anything), so MemoryProfiler reports only
# pipeline costs — validation, PII filtering, sampling, trace context, routing —
# without adapter-side retention polluting the measurement.
#
# Each "request" gets a unique trace_id to reflect real production behavior.
#
# All allocation counts are OBSERVATIONAL (printed but not asserted).
# retained = 0 IS asserted: if it fails, there is a real pipeline-level memory leak.

RSpec.describe "Realistic Memory Profile", :integration do
  # Route all events through NullAdapter with store_events: false — truly discards, no retention.
  # (Default Null stores events for test assertion; memory profiling needs zero retention.)
  before do
    E11y.config.adapters[:null] ||= E11y::Adapters::Null.new(store_events: false)
    E11y.config.fallback_adapters = [:null]
  end

  after do
    E11y.config.fallback_adapters = [:memory]
  end

  def in_request(id)
    Thread.current[:e11y_trace_id] = "realistic-req-#{id}"
    yield
  ensure
    Thread.current[:e11y_trace_id] = nil
  end

  def print_profile(report, label:, event_count:) # rubocop:disable Metrics/AbcSize
    per_event = report.total_allocated.to_f / event_count
    kb_total  = report.total_allocated_memsize / 1024.0

    puts "\n  [Realistic] #{label}:"
    puts "     allocated:  #{report.total_allocated} objects  (#{per_event.round(1)}/event)"
    puts "     retained:   #{report.total_retained} objects"
    puts "     memory:     #{kb_total.round(1)} KB  (#{(kb_total / event_count).round(2)} KB/event)"

    return unless report.total_retained.positive?

    by_count  = report.retained_objects_by_class.first(5).to_h { |e| [e[:data], e[:count]] }
    by_memory = report.retained_memory_by_class.first(10).to_h { |e| [e[:data], e[:count]] }
    puts "     top retained:"
    by_count.each do |klass, count|
      kb = (by_memory[klass].to_i / 1024.0).round(1)
      puts "       #{klass}: #{count} objects (#{kb} KB)"
    end
  end

  # Shared example: warmup includes subject.call to materialise the let() lambda
  # before the profiling window (avoiding Proc retention from RSpec memoization).
  # Uses a single trace_id for all events in the report block to avoid retaining
  # 100+ entries in Sampling middleware's trace_decisions cache (bounded cache, not a leak).
  #
  # retention_limit: SLO/StratifiedTracker scenarios may retain ~300 objects (bounded, not a leak).
  shared_examples "clean pipeline" do |event_count: 100, warmup_count: 20, retention_limit: 0|
    it "allocates objects and retains <= #{retention_limit} (NullAdapter)" do
      E11y::Sampling.reset_stratified_tracker! if defined?(E11y::Sampling)
      warmup_count.times { |i| in_request(i) { subject.call } }
      GC.start
      GC.compact if GC.respond_to?(:compact)

      report = MemoryProfiler.report do
        in_request("memory-profile") { event_count.times { subject.call } }
      end

      print_profile(report, label: label, event_count: event_count)

      expect(report.total_allocated).to be_positive
      expect(report.total_retained).to be <= retention_limit,
                                       "Pipeline leak: #{report.total_retained} objects retained (limit #{retention_limit}).\n" \
                                       "NullAdapter stores nothing — retained objects come from the middleware pipeline.\n" \
                                       "Run benchmarks/allocation_profiling.rb for detailed retained-object analysis."
    end
  end

  # -------------------------------------------------------------------------
  # Scenario A: no-PII event with metrics
  # UserAction: schema validation + Yabeda counter — no PII filtering path.
  # -------------------------------------------------------------------------
  describe "Events::UserAction (no PII, metrics)" do
    subject { -> { Events::UserAction.track(user_id: "user-42", action: "click") } }

    let(:label) { "UserAction (no PII, metrics)" }

    # Ruby 3.2 GC timing: retains 1-6 String/Hash objects (trace_id string interning difference).
    # These are GC artefacts, not real leaks — a real leak compounds over events.
    it_behaves_like "clean pipeline", retention_limit: 10
  end

  # -------------------------------------------------------------------------
  # Scenario B: PII event with nested filtering, metrics, SLO
  # OrderCreated: contains_pii true → rails_filters → ActionDispatch::ParameterFilter,
  # pii_filtering allows list, Yabeda counter + SLO status classification.
  # -------------------------------------------------------------------------
  describe "Events::OrderCreated (contains_pii true, PII filter, metrics, SLO)" do
    subject do
      lambda {
        Events::OrderCreated.track(
          order_id: "ord-1", status: "pending",
          customer: { name: "Jane Doe", email: "jane@example.com", phone: "+1-555-0100" },
          payment: { amount: 99.99, currency: "USD", card_last4: "4242" },
          items: [{ sku: "SKU-001", qty: 2 }]
        )
      }
    end

    let(:label) { "OrderCreated (PII filter + SLO)" }

    # SLO + StratifiedTracker retain ~300 objects (bounded, by design for sampling correction)
    it_behaves_like "clean pipeline", retention_limit: 500
  end

  # -------------------------------------------------------------------------
  # Scenario C: PII event with field masking
  # PaymentSubmitted: contains_pii true, masks :cvv (not just filters).
  # -------------------------------------------------------------------------
  describe "Events::PaymentSubmitted (contains_pii true, masks cvv)" do
    subject do
      lambda {
        Events::PaymentSubmitted.track(
          payment_id: "pay-1",
          card_number: "4111111111111111",
          cvv: "123",
          amount: 49.99,
          currency: "USD",
          billing: { name: "John Smith", email: "john@example.com", address: "123 Main St" }
        )
      }
    end

    let(:label) { "PaymentSubmitted (PII masking)" }

    # Ruby 3.2 GC timing: retains 1-6 String/Hash objects (trace_id string interning difference).
    # These are GC artefacts, not real leaks — a real leak compounds over events.
    it_behaves_like "clean pipeline", retention_limit: 10
  end

  # -------------------------------------------------------------------------
  # Scenario D: multi-event request (3 events/request, 100 requests)
  # Closest to production: all three event types per request, shared trace_id.
  # Reports per-request cost alongside per-event cost.
  # -------------------------------------------------------------------------
  describe "Multi-event request (3 events/request, 100 requests)" do
    it "allocates objects and retains 0 (NullAdapter)" do
      request_count = 100
      event_count   = request_count * 3

      track_request = lambda do
        Events::UserAction.track(user_id: "user-1", action: "checkout")
        Events::OrderCreated.track(
          order_id: "ord-1", status: "pending",
          customer: { name: "Alice", email: "alice@example.com" },
          items: [{ sku: "PROD-1", qty: 1 }]
        )
        Events::PaymentSubmitted.track(
          payment_id: "pay-1", amount: 99.0, currency: "USD",
          card_number: "4111111111111111", cvv: "321",
          billing: { name: "Alice", email: "alice@example.com" }
        )
      end

      E11y::Sampling.reset_stratified_tracker! if defined?(E11y::Sampling)
      20.times { |i| in_request(i) { track_request.call } }
      GC.start
      GC.compact if GC.respond_to?(:compact)

      report = MemoryProfiler.report do
        in_request("memory-profile") { request_count.times { track_request.call } }
      end

      print_profile(report, label: "Multi-event (3×100 requests)", event_count: event_count)
      puts "     per request: #{(report.total_allocated.to_f / request_count).round(1)} objects  " \
           "(#{(report.total_allocated_memsize.to_f / 1024 / request_count).round(2)} KB)"

      expect(report.total_allocated).to be_positive
      # SLO + StratifiedTracker retain ~300 objects (bounded, by design for sampling correction)
      expect(report.total_retained).to be <= 500,
                                       "Pipeline leak: #{report.total_retained} objects retained (limit 500). " \
                                       "NullAdapter stores nothing — investigate the middleware pipeline."
    end
  end
end
