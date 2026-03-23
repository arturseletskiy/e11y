# frozen_string_literal: true
# rubocop:disable all
# Dev-only fixture generator; kept verbose for readability.

# Regenerates public/mocks/v1/*.json with a large, realistic event set.
# Deterministic (Random.new(42)). Run:
#   ruby scripts/generate_mocks.rb
#   E11Y_MOCK_TRACES=52 ruby scripts/generate_mocks.rb   # more traces / events
#
# Mimics DevLog::Query interaction grouping (500ms window).

require "digest"
require "fileutils"
require "json"
require "time"

MOCKS = File.expand_path("../public/mocks/v1", __dir__)
TRACES_DIR = File.join(MOCKS, "traces")

PATHS = %w[
  /up /checkout /orders /orders/new /api/v1/me /api/v1/orders /admin/users
  /webhooks/stripe /internal/health /graphql /sidekiq/busy
].freeze

CONTROLLERS = [
  ["CheckoutController", "show"],
  ["OrdersController", "index"],
  ["OrdersController", "create"],
  ["Orders::PaymentsController", "create"],
  ["Api::V1::MeController", "show"],
  ["Admin::UsersController", "index"],
  ["Webhooks::StripeController", "create"],
  ["GraphqlController", "execute"]
].freeze

JOB_CLASSES = %w[
  ReportExportJob NotificationDispatcherJob SearchIndexJob
  BillingSyncJob WebhookRetryJob CacheWarmJob
].freeze

def uuid4(rng)
  format("%08x-4%03x-%04x-%012x",
         rng.rand(0xFFFFFFFF), rng.rand(0x1000),
         rng.rand(0x4000) + 0x8000,
         rng.rand(0x1000000000000))
end

def span16(rng)
  format("%016x", rng.rand(0x1_0000_0000_0000_0000))
end

def trace_id32(i)
  Digest::SHA256.hexdigest("e11y-overlay-mock-tr-#{i}")[0, 32]
end

def snake_case_class(name)
  base = name.split("::").last
  base.gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr("-", "_")
      .downcase
end

def iso(t)
  t.utc.iso8601(3)
end

def retention_iso(ts_str)
  (Time.parse(ts_str) + (365 * 86_400)).iso8601
end

def parse_started_at(event)
  Time.parse(event.dig("metadata", "started_at") || event["timestamp"])
rescue ArgumentError, TypeError
  nil
end

def build_interaction_rows(all_events, window_ms: 500, limit: 200)
  trace_map = {}
  all_events.each do |e|
    tid = e["trace_id"]
    next unless tid

    started = parse_started_at(e)
    next unless started

    source = e.dig("metadata", "source") || "web"
    entry = trace_map[tid] ||= { started_at: started, has_error: false, source: source }
    entry[:has_error] = true if %w[error fatal].include?(e["severity"])
    entry[:started_at] = started if started < entry[:started_at]
  end

  sorted = trace_map.sort_by { |_, v| v[:started_at] }
  groups = []
  current = nil

  sorted.each do |trace_id, meta|
    if current.nil? || ((meta[:started_at] - current[:last_started_at]) * 1000 > window_ms)
      current = {
        started_at: meta[:started_at],
        last_started_at: meta[:started_at],
        trace_ids: [],
        has_error: false,
        source: meta[:source]
      }
      groups << current
    end
    current[:trace_ids] << trace_id
    current[:has_error] ||= meta[:has_error]
    current[:last_started_at] = meta[:started_at]
  end

  groups.last(limit).reverse.map do |grp|
    {
      "started_at" => grp[:started_at].utc.iso8601(3),
      "trace_ids" => grp[:trace_ids],
      "has_error" => grp[:has_error],
      "source" => grp[:source],
      "traces_count" => grp[:trace_ids].size
    }
  end
end

def build_web_trace_events(rng, trace_id:, req_id:, path:, method:, controller:, action:, started:, order_id:)
  base_meta = lambda do |extra = {}|
    {
      "source" => "web",
      "started_at" => iso(started),
      "request_id" => req_id,
      "path" => path,
      "method" => method,
      "controller" => controller,
      "action" => action,
      "duration_ms" => rng.rand(1..120)
    }.merge(extra)
  end

  offset = 0.0
  bump = -> { offset += (0.010 + (rng.rand * 0.006)); started + offset }

  evs = []
  t = bump.call
  evs << {
    "id" => uuid4(rng), "timestamp" => iso(t), "event_name" => "Events::LogInfo",
    "severity" => "info", "version" => 1, "trace_id" => trace_id,
    "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
    "retention_until" => retention_iso(iso(t)),
    "payload" => {
      "message" => "Started #{method} \"#{path}\" for ::1 at #{t.strftime('%Y-%m-%d %H:%M:%S')} +0000",
      "level" => "info"
    },
    "metadata" => base_meta.call("duration_ms" => rng.rand(0..3))
  }

  t = bump.call
  ok = rng.rand > 0.08
  evs << {
    "id" => uuid4(rng), "timestamp" => iso(t), "event_name" => "Events::ApiRequest",
    "severity" => ok ? "info" : "warn", "version" => 1, "trace_id" => trace_id,
    "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
    "retention_until" => retention_iso(iso(t)),
    "payload" => {
      "endpoint" => "#{method} #{path}",
      "status" => ok ? "ok" : "slow",
      "http_status" => ok ? 200 : 429
    },
    "metadata" => base_meta.call
  }

  if rng.rand < 0.65
    t = bump.call
    evs << {
      "id" => uuid4(rng), "timestamp" => iso(t), "event_name" => "Events::PostDebug",
      "severity" => "debug", "version" => 1, "trace_id" => trace_id,
      "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
      "retention_until" => retention_iso(iso(t)),
      "payload" => {
        "message" => "  \u2192 #{['CACHE', 'SQL', 'Render'].sample(random: rng)} #{path} — #{rng.rand(1..48)}.#{rng.rand(0..9)}ms"
      },
      "metadata" => base_meta.call("duration_ms" => rng.rand(1..8))
    }
  end

  extra = rng.rand(1..3)
  extra.times do
    t = bump.call
    evs << {
      "id" => uuid4(rng), "timestamp" => iso(t), "event_name" => "Events::PostDebug",
      "severity" => "debug", "version" => 1, "trace_id" => trace_id,
      "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
      "retention_until" => retention_iso(iso(t)),
      "payload" => {
        "message" => "  \u2192 #{['CACHE', 'SQL', 'Render', 'N+1'].sample(random: rng)} — #{path} id=#{rng.rand(1..50_000)}"
      },
      "metadata" => base_meta.call("duration_ms" => rng.rand(1..25))
    }
  end

  if path != "/up"
    t = bump.call
    evs << {
      "id" => uuid4(rng), "timestamp" => iso(t), "event_name" => "Events::OrderCreated",
      "severity" => "success", "version" => 1, "trace_id" => trace_id,
      "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
      "retention_until" => retention_iso(iso(t)),
      "payload" => {
        "order_id" => order_id,
        "status" => %w[pending_payment completed cancelled].sample(random: rng),
        "customer" => { "id" => rng.rand(1..10_000), "email" => "[FILTERED]", "locale" => "en" },
        "items" => [
          { "sku" => "SKU-#{rng.rand(100..999)}", "qty" => 1, "unit_price" => rng.rand(5.0..499.0).round(2) }
        ]
      },
      "metadata" => base_meta.call
    }
  end

  if rng.rand < 0.14
    t = bump.call
    evs << {
      "id" => uuid4(rng), "timestamp" => iso(t), "event_name" => "Events::PaymentFailed",
      "severity" => "error", "version" => 1, "trace_id" => trace_id,
      "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
      "retention_until" => retention_iso(iso(t)),
      "payload" => {
        "order_id" => order_id,
        "amount" => rng.rand(10.0..500.0).round(2),
        "gateway" => "stripe",
        "decline_code" => %w[insufficient_funds expired_card processing_error].sample(random: rng)
      },
      "metadata" => base_meta.call
    }
  elsif rng.rand < 0.22
    t = bump.call
    evs << {
      "id" => uuid4(rng), "timestamp" => iso(t), "event_name" => "Events::UserAction",
      "severity" => "warn", "version" => 1, "trace_id" => trace_id,
      "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
      "retention_until" => retention_iso(iso(t)),
      "payload" => { "action" => "checkout_step", "step" => "review", "flags" => ["rate_limit_near"] },
      "metadata" => base_meta.call
    }
  end

  t = bump.call
  evs << {
    "id" => uuid4(rng), "timestamp" => iso(t), "event_name" => "Events::LogInfo",
    "severity" => "info", "version" => 1, "trace_id" => trace_id,
    "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
    "retention_until" => retention_iso(iso(t)),
    "payload" => { "message" => "Completed #{method} #{path} in #{rng.rand(12..890)}ms", "level" => "info" },
    "metadata" => base_meta.call("duration_ms" => rng.rand(8..200))
  }

  evs
end

def job_event_bundle(rng, trace_id:, started:, idx:, job_class:, jid:)
  t = started + (idx * 0.55) + (rng.rand * 0.08)
  ts = iso(t)
  base_meta = { "source" => "job", "started_at" => iso(started), "duration_ms" => rng.rand(2..900) }

  case idx
  when 0
    {
      "id" => uuid4(rng), "timestamp" => ts, "event_name" => "Events::BackgroundJobStarted",
      "severity" => "info", "version" => 1, "trace_id" => trace_id,
      "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
      "retention_until" => retention_iso(ts),
      "payload" => {
        "job_class" => job_class,
        "job_id" => jid,
        "queue" => %w[default critical low].sample(random: rng),
        "arguments" => [{ "batch_id" => rng.rand(1..99_999), "shard" => rng.rand(0..15) }],
        "enqueued_at" => iso(started - rng.rand(0..3))
      },
      "metadata" => base_meta
    }
  when 1
    {
      "id" => uuid4(rng), "timestamp" => ts, "event_name" => "Events::ReportCreated",
      "severity" => "info", "version" => 1, "trace_id" => trace_id,
      "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
      "retention_until" => retention_iso(ts),
      "payload" => {
        "title" => "Export batch #{rng.rand(1000..9999)}",
        "description" => "Queued by #{job_class}",
        "employee_ids" => [rng.rand(1..200), rng.rand(1..200)].uniq,
        "author" => "system"
      },
      "metadata" => base_meta
    }
  else
    fatal = rng.rand < 0.09
    {
      "id" => uuid4(rng), "timestamp" => ts,
      "event_name" => fatal ? "Events::ReportExportCompleted" : "Events::LogInfo",
      "severity" => fatal ? "fatal" : "info",
      "version" => 1, "trace_id" => trace_id,
      "span_id" => span16(rng), "service_name" => "dummy", "environment" => "development",
      "retention_until" => retention_iso(ts),
      "payload" => if fatal
                     {
                       "report_id" => rng.rand(1000..9999),
                       "error" => "No space left on device",
                       "exception" => {
                         "class" => "Errno::ENOSPC",
                         "message" => "No space left on device @ rb_sysopen",
                         "backtrace" => [
                           "app/jobs/#{snake_case_class(job_class)}.rb:#{rng.rand(20..120)}:in `perform'",
                           "activejob (#{rng.rand(6..8)}.#{rng.rand(0..2)}.0) lib/active_job/execution.rb:68:in `perform_now'"
                         ]
                       }
                     }
                   else
                     { "message" => "Job #{job_class} done shard=#{rng.rand(0..15)}", "level" => "info" }
                   end,
      "metadata" => base_meta
    }
  end
end

def generate
  rng = Random.new(42)
  base = Time.utc(2026, 3, 20, 9, 47, 12)
  elapsed_ms = 0
  all = []
  traces = {} # trace_id => [events chrono]

  # Scale: ~24 traces → ~150 events (~10× the original 15-event fixture). Increase `num_traces` for more.
  num_traces = Integer(ENV.fetch("E11Y_MOCK_TRACES", "24"), 10)
  num_traces.times do |i|
    tid = trace_id32(i)
    # Cluster some starts within 400ms for multi-trace interactions
    burst = (i % 11).zero? ? rng.rand(80..420) : rng.rand(350..2400)
    elapsed_ms += burst
    started = base + (elapsed_ms / 1000.0)

    if (i % 7).zero?
      job_class = JOB_CLASSES.sample(random: rng)
      jid = uuid4(rng)
      events = []
      n = 3 + rng.rand(0..2)
      n.times do |j|
        ev = job_event_bundle(rng, trace_id: tid, started: started, idx: j, job_class: job_class, jid: jid)
        events << ev if ev
      end
    else
      path = PATHS.sample(random: rng)
      method = if path == "/webhooks/stripe" || path == "/graphql"
                 "POST"
               else
                 "GET"
               end
      pair = CONTROLLERS.sample(random: rng)
      req_id = "req-#{tid[0, 8]}-#{i}"
      order_id = format("ord_%06d", rng.rand(1..999_999))
      events = build_web_trace_events(
        rng,
        trace_id: tid,
        req_id: req_id,
        path: path,
        method: method,
        controller: pair[0],
        action: pair[1],
        started: started,
        order_id: order_id
      )
    end

    # Ensure chronological order within trace
    events.compact!
    events.sort_by! { |e| Time.parse(e["timestamp"]) }
    events.each { |e| all << e }
    traces[tid] = events
  end

  recent = all.sort_by { |e| Time.parse(e["timestamp"]) }.reverse
  interactions = build_interaction_rows(all, window_ms: 500, limit: 120)

  FileUtils.rm_rf(TRACES_DIR)
  FileUtils.mkdir_p(TRACES_DIR)
  traces.each do |tid, evs|
    dir = File.join(TRACES_DIR, tid)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "events.json"), JSON.pretty_generate(evs))
  end

  File.write(File.join(MOCKS, "events/recent.json"), JSON.pretty_generate(recent))
  File.write(File.join(MOCKS, "interactions.json"), JSON.pretty_generate(interactions))

  puts "Wrote #{recent.size} events in #{traces.size} traces, #{interactions.size} interaction rows → #{MOCKS}"
end

generate

# rubocop:enable all
