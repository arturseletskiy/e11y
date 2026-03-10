# frozen_string_literal: true

require "rails_helper"
require "memory_profiler"

# Realistic memory profile for production-typical event tracking.
#
# Uses real event classes from the dummy app (contains_pii true, metrics, SLO),
# unique trace_ids per "request", and the full middleware pipeline.
#
# ## IMPORTANT: retention numbers explained
#
# Scenarios A–D use the InMemory adapter (fallback_adapters: [:memory]), which STORES
# every event_data Hash. Each Hash contains: timestamp (Time), retention_period
# (ActiveSupport::Duration from `30.days`), payload, context, etc. — roughly 12–15 objects.
# 100 events → 100 stored Hashes → ~1200–2500 "retained" objects in MemoryProfiler output.
#
# This is TEST INFRASTRUCTURE retention, NOT a production pipeline leak.
# In production, Loki/Sentry/OTel adapters fire-and-forget — they don't keep event_data.
#
# Scenario E isolates pipeline-only allocations by clearing the adapter after each event,
# which gives the production-accurate picture: retained = 0 for all event types.
#
# ## Isolation analysis (verified with tmp spec):
#   A: unique trace + adapter retains → retained=1522  (100 event_data Hashes)
#   B: unique trace + adapter cleared → retained=0
#   C: fixed trace  + adapter cleared → retained=0
#   A→B delta = 1522 objects  ← entirely from InMemory adapter storage
#   B→C delta = 0 objects     ← @trace_decisions cache is NOT a retention source here
#
# All examples are OBSERVATIONAL (no hard thresholds). Purpose: document
# production-realistic allocation baselines for future optimization targets.

RSpec.describe "Realistic Memory Profile", :integration do
  let(:adapter) { E11y.config.adapters[:memory] }

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
      kb_class = (by_memory[klass].to_i / 1024.0).round(1)
      puts "       #{klass}: #{count} objects (#{kb_class} KB)"
    end
  end

  # -------------------------------------------------------------------------
  # Scenarios A–D: full InMemory adapter storage (shows test infra retention)
  # Retained objects = event_data Hashes stored by InMemory adapter.
  # See file header for explanation.
  # -------------------------------------------------------------------------

  describe "Events::UserAction (no PII, has metrics)" do
    it "observes allocation profile — production baseline" do
      payload = { user_id: "user-42", action: "click" }

      # Warmup: stabilise Yabeda counter registration, dry-schema compilation
      20.times { |i| in_request(i) { Events::UserAction.track(**payload) } }
      GC.start
      GC.compact if GC.respond_to?(:compact)

      report = MemoryProfiler.report do
        100.times do |i|
          in_request(100 + i) { Events::UserAction.track(**payload) }
        end
      end

      print_realistic_report(report, label: "UserAction (no PII, metrics)", event_count: 100)
      puts "     (retention from InMemory adapter storing #{adapter.event_count} events)"

      expect(report.total_allocated).to be_positive
    end
  end

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
      puts "     (retention from InMemory adapter storing #{adapter.event_count} events)"

      expect(report.total_allocated).to be_positive
    end
  end

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
      puts "     (retention from InMemory adapter storing #{adapter.event_count} events)"

      expect(report.total_allocated).to be_positive
    end
  end

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
      puts "     per request: #{(report.total_allocated.to_f / request_count).round(1)} objects  " \
           "(#{(report.total_allocated_memsize.to_f / 1024 / request_count).round(2)} KB/request)"
      puts "     (retention from InMemory adapter storing #{adapter.event_count} events)"

      expect(report.total_allocated).to be_positive
    end
  end

  # -------------------------------------------------------------------------
  # Scenario E: Production-accurate pipeline profile
  # Clears InMemory adapter after each event to isolate pipeline allocations
  # from adapter storage overhead — matches Loki/Sentry/OTel production behavior.
  #
  # Expected: retained = 0 for all event types (verified in isolation analysis).
  # Alloc/event figures here are the REAL production pipeline cost.
  # -------------------------------------------------------------------------
  describe "Production-accurate pipeline profile (adapter cleared per event)" do
    it "observes pipeline-only allocations — no adapter storage overhead" do
      payloads = {
        action:   { user_id: "user-1", action: "click" },
        order:    { order_id: "ord-1", status: "pending",
                    customer: { name: "Alice", email: "alice@example.com" },
                    items: [{ sku: "PROD-1", qty: 1 }] },
        payment:  { payment_id: "pay-1", amount: 49.99, currency: "USD",
                    card_number: "4111111111111111", cvv: "123",
                    billing: { name: "Alice", email: "alice@example.com" } }
      }

      # Warmup
      20.times do |i|
        in_request(i) do
          Events::UserAction.track(**payloads[:action])
          Events::OrderCreated.track(**payloads[:order])
          Events::PaymentSubmitted.track(**payloads[:payment])
          adapter.clear!
        end
      end
      GC.start
      GC.compact if GC.respond_to?(:compact)

      request_count = 100
      event_count   = request_count * 3

      report = MemoryProfiler.report do
        request_count.times do |i|
          in_request(100 + i) do
            Events::UserAction.track(**payloads[:action])
            Events::OrderCreated.track(**payloads[:order])
            Events::PaymentSubmitted.track(**payloads[:payment])
            adapter.clear!
          end
        end
      end

      per_event   = report.total_allocated.to_f / event_count
      per_request = report.total_allocated.to_f / request_count
      kb_per_req  = report.total_allocated_memsize.to_f / 1024 / request_count

      puts "\n  [Realistic-Prod] pipeline-only (adapter cleared, 3 event types × 100 requests):"
      puts "     allocated: #{report.total_allocated} objects total"
      puts "       per event:   #{per_event.round(1)} objects"
      puts "       per request: #{per_request.round(1)} objects  (#{kb_per_req.round(2)} KB)"
      puts "     retained:  #{report.total_retained} objects  (expect 0 — no adapter storage)"

      if report.total_retained.positive?
        puts "     top retained (UNEXPECTED — investigate):"
        by_count  = report.retained_objects_by_class.first(5).map { |e| [e[:data], e[:count]] }.to_h
        by_memory = report.retained_memory_by_class.first(10).map { |e| [e[:data], e[:count]] }.to_h
        by_count.each do |klass, count|
          kb_class = (by_memory[klass].to_i / 1024.0).round(1)
          puts "       #{klass}: #{count} objects (#{kb_class} KB)"
        end
      end

      expect(report.total_allocated).to be_positive
      # Retention from the pipeline itself (no adapter storage) should be 0.
      # If this fails, it indicates a real pipeline-level leak.
      expect(report.total_retained).to eq(0),
        "Pipeline leak: #{report.total_retained} objects retained without adapter storage. " \
        "This is NOT from InMemory adapter — investigate the middleware pipeline."
    end
  end
end
