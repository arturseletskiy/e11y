# frozen_string_literal: true

require "rails_helper"
require "memory_profiler"

# Realistic memory profile for production-typical event tracking.
#
# Unlike spec/e11y/memory_spec.rb, this test:
#   - Uses fully-configured event classes from the dummy app (contains_pii true, metrics, SLO)
#   - Does NOT fix Thread.current[:e11y_trace_id] — each "request" gets a unique trace_id
#     as in production, so @trace_decisions cache grows O(unique_requests)
#   - Passes through the full middleware pipeline: validation, sampling, PII filtering,
#     trace context, routing, rate limiting, audit signing
#   - All examples are OBSERVATIONAL: they print measurements and have no hard thresholds.
#     The purpose is to establish a documented baseline and catch surprises during review.

RSpec.describe "Realistic Memory Profile", :integration do
  # Helper: simulate one production "request" by setting a unique trace_id,
  # yielding, then clearing. This matches real Railtie middleware behavior.
  def in_request(id)
    Thread.current[:e11y_trace_id] = "realistic-req-#{id}"
    yield
  ensure
    Thread.current[:e11y_trace_id] = nil
  end

  def print_realistic_report(report, label:, event_count:)
    per_event = report.total_allocated.to_f / event_count
    kb = report.total_allocated_memsize / 1024.0

    puts "\n  [Realistic] #{label}:"
    puts "     allocated: #{report.total_allocated} objects  (#{per_event.round(1)}/event)"
    puts "     retained:  #{report.total_retained} objects"
    puts "     memory:    #{kb.round(1)} KB  (#{(kb / event_count).round(2)} KB/event)"

    return unless report.total_retained.positive?

    # retained_objects_by_class: sorted by object count desc, each {data: ClassName, count: N_objects}
    # retained_memory_by_class:  sorted by bytes desc,        each {data: ClassName, count: N_bytes}
    puts "     top retained (objects / KB):"
    by_count  = report.retained_objects_by_class.first(5).map { |e| [e[:data], e[:count]] }.to_h
    by_memory = report.retained_memory_by_class.first(10).map { |e| [e[:data], e[:count]] }.to_h
    by_count.each do |klass, count|
      kb = (by_memory[klass].to_i / 1024.0).round(1)
      puts "       #{klass}: #{count} objects (#{kb} KB)"
    end
  end

  # -------------------------------------------------------------------------
  # Scenario A: no-PII event with metrics (simplest production event)
  # UserAction has validation + metrics counter but NO PII filtering.
  # This is the fastest expected path — use as a "realistic baseline".
  # -------------------------------------------------------------------------
  describe "Events::UserAction (no PII, has metrics)" do
    it "observes allocation profile — production baseline" do
      payload = { user_id: "user-42", action: "click" }

      # Warmup: stabilise Yabeda counter registration, dry-schema compilation,
      # and JIT before the profiling window.
      20.times { |i| in_request(i) { Events::UserAction.track(**payload) } }
      GC.start
      GC.compact if GC.respond_to?(:compact)

      report = MemoryProfiler.report do
        100.times do |i|
          in_request(100 + i) { Events::UserAction.track(**payload) }
        end
      end

      print_realistic_report(report, label: "UserAction (no PII, metrics)", event_count: 100)

      # Non-failing sanity check — just verifies the pipeline ran
      expect(report.total_allocated).to be_positive
    end
  end

  # -------------------------------------------------------------------------
  # Scenario B: PII event with nested filtering, metrics, SLO (heaviest path)
  # Events::OrderCreated exercises:
  #   - contains_pii true → tier2 → ActiveSupport::ParameterFilter
  #   - pii_filtering allows list → nested hash scan
  #   - metrics counter with :status tag → Yabeda recording
  #   - SLO tracking → status classification
  # -------------------------------------------------------------------------
  describe "Events::OrderCreated (contains_pii true, PII filter, metrics, SLO)" do
    it "observes allocation profile — full production pipeline" do
      payload = {
        order_id: "ord-warmup",
        status: "pending",
        customer: { name: "Jane Doe", email: "jane@example.com", phone: "+1-555-0100" },
        payment:  { amount: 99.99, currency: "USD", card_last4: "4242" },
        items:    [{ sku: "SKU-001", qty: 2 }, { sku: "SKU-002", qty: 1 }]
      }

      20.times { |i| in_request(i) { Events::OrderCreated.track(**payload) } }
      GC.start
      GC.compact if GC.respond_to?(:compact)

      report = MemoryProfiler.report do
        100.times do |i|
          in_request(100 + i) { Events::OrderCreated.track(**payload) }
        end
      end

      print_realistic_report(report, label: "OrderCreated (contains_pii true, SLO)", event_count: 100)

      expect(report.total_allocated).to be_positive
    end
  end

  # -------------------------------------------------------------------------
  # Scenario C: payment event — contains_pii true, masks :cvv
  # PaymentSubmitted exercises the masking path (not just filtering).
  # -------------------------------------------------------------------------
  describe "Events::PaymentSubmitted (contains_pii true, masks cvv)" do
    it "observes allocation profile — PII masking path" do
      payload = {
        payment_id: "pay-001",
        card_number: "4111111111111111",
        cvv: "123",
        amount: 49.99,
        currency: "USD",
        billing: { name: "John Smith", email: "john@example.com", address: "123 Main St" }
      }

      20.times { |i| in_request(i) { Events::PaymentSubmitted.track(**payload) } }
      GC.start
      GC.compact if GC.respond_to?(:compact)

      report = MemoryProfiler.report do
        100.times do |i|
          in_request(100 + i) { Events::PaymentSubmitted.track(**payload) }
        end
      end

      print_realistic_report(report, label: "PaymentSubmitted (masks cvv)", event_count: 100)

      expect(report.total_allocated).to be_positive
    end
  end

  # -------------------------------------------------------------------------
  # Scenario D: multi-event request simulation
  # Closest to real production: each "request" tracks 3 events sharing one trace_id.
  # Shows allocation cost per request (not per event) and cumulative retention.
  # -------------------------------------------------------------------------
  describe "Multi-event request simulation (3 events/request, 100 requests)" do
    it "observes allocation profile — realistic request throughput" do
      order_payload = {
        order_id: "ord-001", status: "pending",
        customer: { name: "Alice", email: "alice@example.com" },
        items: [{ sku: "PROD-1", qty: 1 }]
      }
      action_payload  = { user_id: "user-1", action: "checkout" }
      payment_payload = { payment_id: "pay-001", amount: 99.0, currency: "USD",
                          card_number: "4111111111111111", cvv: "321" }

      # Warmup
      20.times do |i|
        in_request(i) do
          Events::UserAction.track(**action_payload)
          Events::OrderCreated.track(**order_payload)
          Events::PaymentSubmitted.track(**payment_payload)
        end
      end
      GC.start
      GC.compact if GC.respond_to?(:compact)

      request_count = 100
      event_count   = request_count * 3

      report = MemoryProfiler.report do
        request_count.times do |i|
          in_request(100 + i) do
            Events::UserAction.track(**action_payload)
            Events::OrderCreated.track(**order_payload)
            Events::PaymentSubmitted.track(**payment_payload)
          end
        end
      end

      print_realistic_report(report, label: "Multi-event (3 events × 100 requests)", event_count: event_count)

      per_request = report.total_allocated.to_f / request_count
      kb_per_req  = report.total_allocated_memsize.to_f / 1024 / request_count
      puts "     per request: #{per_request.round(1)} objects  (#{kb_per_req.round(2)} KB/request)"
      puts "     NOTE: retained ~#{request_count} objects expected (sampling @trace_decisions cache, O(unique_trace_ids))"

      expect(report.total_allocated).to be_positive
    end
  end
end
