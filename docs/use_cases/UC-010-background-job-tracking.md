# UC-010: Background Job Tracking

**Status:** MVP Feature  
**Complexity:** Intermediate  
**Setup Time:** 20-30 minutes  
**Target Users:** Backend Developers, SRE, DevOps

---

## 📋 Overview

### Problem Statement

**The invisible failure:**
```ruby
# ❌ NO VISIBILITY: Background jobs failing silently
class SendEmailJob < ApplicationJob
  def perform(user_id)
    user = User.find(user_id)
    UserMailer.welcome(user).deliver_now
    # What if this fails? 
    # - No log (unless you remember to add it)
    # - No metric
    # - No trace correlation with request that enqueued it
    # - Can't see job duration/performance trends
  end
end

# Problems:
# - Enqueued from request A (trace_id: abc-123)
# - Executes later (NEW trace_id: xyz-789)
# - Lost correlation between request and job!
# - Silent failures (retries happen but you don't know why)
# - No SLO tracking (how many jobs succeed? How fast?)
# - No visibility into job queue health
```

### E11y Solution

**Automatic job instrumentation with full traceability:**
```ruby
# ✅ AUTOMATIC TRACKING: Zero-config job observability
class SendEmailJob < ApplicationJob
  def perform(user_id)
    # E11y automatically tracks:
    # - Job started
    # - Job succeeded/failed
    # - Duration
    # - Trace ID (from enqueuing request!)
    # - Retry attempts
    # - Queue metrics
    
    user = User.find(user_id)
    UserMailer.welcome(user).deliver_now
    
    # No explicit tracking needed! ✨
  end
end

# Result (automatic events):
# 1. job.enqueued (trace_id: abc-123)
# 2. job.started (trace_id: abc-123 - preserved!)
# 3. job.succeeded (trace_id: abc-123, duration_ms: 1250)
#
# Metrics (automatic):
# - jobs_total{job="SendEmailJob",status="success"} = 1
# - jobs_duration_ms{job="SendEmailJob"} = 1250
# - jobs_queue_size{queue="default"} = 45
```

---

## 🎯 Features

> **Implementation:** See [ADR-008: Rails Integration](../architecture/ADR-008-rails-integration.md) for complete architecture, including [Section 5: Sidekiq Integration](../architecture/ADR-008-rails-integration.md#5-sidekiq-integration), [Section 6: ActiveJob Integration](../architecture/ADR-008-rails-integration.md#6-activejob-integration), and [Section 5.3: Job-Scoped Buffer](../architecture/ADR-008-rails-integration.md#53-job-scoped-buffer).

### 1. Automatic Instrumentation

**Enable Sidekiq and Active Job integration:**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.rails_instrumentation_enabled = true # ActiveJob ASN events (when using Rails)
  config.sidekiq_enabled = true
  config.active_job_enabled = true
end
```

**What gets tracked automatically:**
- ✅ Job enqueued (when `.perform_later` called)
- ✅ Job started (when worker picks it up)
- ✅ Job succeeded (on success)
- ✅ Job failed (on error)
- ✅ Job retried (after failure)
- ✅ Duration (total execution time)
- ✅ Latency (time in queue before execution)
- ✅ Trace ID (preserved from enqueuing request!)

---

### 2. Trace Correlation

**Automatic trace_id propagation:**
```ruby
# Controller (trace_id: abc-123)
class OrdersController < ApplicationController
  def create
    order = Order.create!(order_params)
    
    # Enqueue job (trace_id automatically passed!)
    SendOrderConfirmationJob.perform_later(order.id)
    
    render json: order
  end
end

# Job (trace_id: abc-123 - preserved!)
class SendOrderConfirmationJob < ApplicationJob
  def perform(order_id)
    # E11y::TraceId.current == 'abc-123' ✅
    
    order = Order.find(order_id)
    OrderMailer.confirmation(order).deliver_now
  end
end

# Timeline in Grafana: {trace_id="abc-123"}
# 10:00:00.000 [controller] order.created
# 10:00:00.050 [controller] job.enqueued (job: SendOrderConfirmation)
# 10:00:02.000 [job] job.started (job: SendOrderConfirmation, latency: 1950ms)
# 10:00:03.200 [job] email.sent
# 10:00:03.250 [job] job.succeeded (duration: 1250ms)
# → Complete trace across request + background job!
```

---

### 3. Retry Tracking

**Visibility into retry behavior:**
```ruby
class UnreliableApiJob < ApplicationJob
  retry_on ApiError, wait: :exponentially_longer, attempts: 5
  
  def perform(data)
    # Might fail, will retry...
    UnreliableApi.call(data)
  end
end

# E11y automatically tracks retries:
# Attempt 1: job.started → job.failed (error: ApiTimeout)
# Attempt 2 (after 3s): job.retried (attempt: 2) → job.failed
# Attempt 3 (after 18s): job.retried (attempt: 3) → job.failed
# Attempt 4 (after 83s): job.retried (attempt: 4) → job.succeeded ✅

# Metrics:
# jobs_retried_total{job="UnreliableApiJob",attempt="2"} = 1
# jobs_retried_total{job="UnreliableApiJob",attempt="3"} = 1
# jobs_retried_total{job="UnreliableApiJob",attempt="4"} = 1
# jobs_retry_exhausted_total{job="UnreliableApiJob"} = 0 (succeeded on attempt 4)
```

---

### 4. Queue Health Metrics

**Monitor queue depth and processing:**
```ruby
# Automatic metrics (updated every 10s):
# jobs_queue_size{queue="default"} = 145
# jobs_queue_size{queue="mailers"} = 23
# jobs_queue_size{queue="critical"} = 2
#
# jobs_queue_latency_seconds{queue="default"} = 5.2  # Oldest job waiting 5.2s
# jobs_enqueued_total{queue="default"} = 1234
# jobs_processed_total{queue="default",status="success"} = 1200
# jobs_processed_total{queue="default",status="failed"} = 34

# Prometheus alerts:
# - Queue backlog: jobs_queue_size > 1000
# - High latency: jobs_queue_latency_seconds > 60
# - High failure rate: rate(jobs_processed_total{status="failed"}[5m]) > 10
```

---

### 5. Job-Specific Events

> **Note:** E11y supports **job-scoped buffering** similar to [UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md). Debug events within a job are buffered and only flushed if the job fails. See [ADR-001 Section 3.4: Request-Scoped Buffer](../architecture/ADR-001-architecture.md#34-request-scoped-buffer) for implementation details (same architecture applies to jobs).

**Emit custom events within jobs:**
```ruby
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    
    # Custom events (inherit trace_id automatically!)
    Events::OrderProcessingStarted.track(order_id: order.id)
    
    # Step 1
    Events::InventoryChecked.track(
      order_id: order.id,
      items_available: check_inventory(order)
    )
    
    # Step 2
    Events::PaymentCaptured.track(
      order_id: order.id,
      amount: capture_payment(order)
    )
    
    # Step 3
    Events::ShipmentScheduled.track(
      order_id: order.id,
      estimated_delivery: schedule_shipment(order)
    )
    
    Events::OrderProcessingCompleted.track(
      order_id: order.id,
      severity: :success
    )
  end
end

# Timeline: {trace_id="abc-123"}
# 10:00:00 [controller] order.created
# 10:00:01 [controller] job.enqueued
# 10:00:05 [job] job.started
# 10:00:05 [job] order.processing.started
# 10:00:06 [job] inventory.checked
# 10:00:08 [job] payment.captured
# 10:00:10 [job] shipment.scheduled
# 10:00:10 [job] order.processing.completed
# 10:00:10 [job] job.succeeded
# → Complete observability into job execution!
```

---

## 💻 Implementation Examples

### Example 1: Email Job with Retry

```ruby
class SendWelcomeEmailJob < ApplicationJob
  queue_as :mailers
  
  retry_on Net::SMTPServerBusy, wait: 5.seconds, attempts: 3
  discard_on Net::SMTPFatalError  # Don't retry permanent failures
  
  def perform(user_id)
    user = User.find(user_id)
    
    # Track email sending (custom event)
    Events::EmailSending.track(
      user_id: user.id,
      email: user.email,
      template: 'welcome'
    )
    
    UserMailer.welcome(user).deliver_now
    
    # Track success
    Events::EmailSent.track(
      user_id: user.id,
      template: 'welcome',
      severity: :success
    )
  end
end

# Automatic tracking (by E11y):
# 1. job.enqueued (when perform_later called)
# 2. job.started (when worker picks up)
# 3. email.sending (custom event)
# 4. email.sent (custom event)
# 5. job.succeeded
#
# If SMTP error:
# 1. job.enqueued
# 2. job.started
# 3. email.sending
# 4. job.failed (error: Net::SMTPServerBusy)
# 5. job.retried (attempt: 2, after 5s)
# 6. job.started (attempt 2)
# ... repeat until success or exhausted
```

---

### Example 2: Batch Processing Job

```ruby
class ProcessBatchJob < ApplicationJob
  queue_as :batch_processing
  
  def perform(batch_id)
    batch = Batch.find(batch_id)
    
    # Track batch processing
    Events::BatchProcessingStarted.track(
      batch_id: batch.id,
      total_items: batch.items.count
    )
    
    processed = 0
    failed = 0
    
    batch.items.find_each do |item|
      begin
        process_item(item)
        processed += 1
        
        # Progress update every 100 items
        if processed % 100 == 0
          Events::BatchProgress.track(
            batch_id: batch.id,
            processed: processed,
            total: batch.items.count,
            progress_pct: (processed.to_f / batch.items.count * 100).round(2)
          )
        end
      rescue => e
        failed += 1
        Events::BatchItemFailed.track(
          batch_id: batch.id,
          item_id: item.id,
          error: e.message,
          severity: :error
        )
      end
    end
    
    # Summary
    Events::BatchProcessingCompleted.track(
      batch_id: batch.id,
      total_items: batch.items.count,
      processed: processed,
      failed: failed,
      success_rate: (processed.to_f / batch.items.count * 100).round(2),
      severity: failed == 0 ? :success : :warn
    )
  end
end

# Metrics (automatic from events):
# batch_processing_items_total{batch_id="123"} = 1000
# batch_processing_items_processed{batch_id="123"} = 980
# batch_processing_items_failed{batch_id="123"} = 20
# batch_processing_success_rate{batch_id="123"} = 98.0
```

---

### Example 3: Scheduled Job (Cron)

```ruby
class DailyReportJob < ApplicationJob
  queue_as :reports
  
  # Scheduled via whenever gem or Sidekiq-cron
  def perform
    # Track report generation
    Events::ReportGenerationStarted.track(
      report_type: 'daily_summary',
      date: Date.today
    )
    
    begin
      # Generate report
      report = generate_daily_report
      
      # Track success
      Events::ReportGenerated.track(
        report_type: 'daily_summary',
        date: Date.today,
        record_count: report.records.count,
        file_size_bytes: report.file.size,
        severity: :success
      )
      
      # Send to stakeholders
      ReportMailer.daily_summary(report).deliver_now
      
    rescue => e
      # Track failure
      Events::ReportGenerationFailed.track(
        report_type: 'daily_summary',
        date: Date.today,
        error_class: e.class.name,
        error_message: e.message,
        severity: :error
      )
      
      # Alert ops team
      raise  # Will trigger Sidekiq retry
    end
  end
end

# Monitoring:
# - Daily at 6 AM: job.started
# - Success rate: jobs_processed_total{job="DailyReportJob",status="success"} / total
# - Alert if failed: jobs_processed_total{job="DailyReportJob",status="failed"} > 0
```

---

### Example 4: Chain of Jobs

```ruby
class OrderFulfillmentWorkflow
  def self.start(order_id)
    # Step 1: Validate order
    ValidateOrderJob.perform_later(order_id)
  end
end

class ValidateOrderJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    
    Events::OrderValidationStarted.track(order_id: order.id)
    
    if order.valid_for_fulfillment?
      Events::OrderValidated.track(order_id: order.id, severity: :success)
      
      # Chain to next step
      ChargePaymentJob.perform_later(order_id)
    else
      Events::OrderValidationFailed.track(
        order_id: order.id,
        errors: order.validation_errors,
        severity: :error
      )
    end
  end
end

class ChargePaymentJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    
    Events::PaymentCharging.track(order_id: order.id, amount: order.total)
    
    payment = PaymentGateway.charge(order)
    
    Events::PaymentCharged.track(
      order_id: order.id,
      transaction_id: payment.id,
      severity: :success
    )
    
    # Chain to next step
    FulfillOrderJob.perform_later(order_id)
  end
end

class FulfillOrderJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    
    Events::OrderFulfillmentStarted.track(order_id: order.id)
    
    shipment = create_shipment(order)
    
    Events::OrderFulfilled.track(
      order_id: order.id,
      shipment_id: shipment.id,
      tracking_number: shipment.tracking_number,
      severity: :success
    )
  end
end

# Timeline (same trace_id across all jobs!):
# 10:00:00 [controller] order.created (trace_id: abc-123)
# 10:00:01 [job] order.validation.started (trace_id: abc-123)
# 10:00:02 [job] order.validated (trace_id: abc-123)
# 10:00:03 [job] payment.charging (trace_id: abc-123)
# 10:00:05 [job] payment.charged (trace_id: abc-123)
# 10:00:06 [job] order.fulfillment.started (trace_id: abc-123)
# 10:00:10 [job] order.fulfilled (trace_id: abc-123)
# → Complete workflow trace!
```

---

### 6. Sidekiq Middleware Implementation (C17, C18 Resolutions) ⚠️

> **Reference:** See [ADR-005 §8.3 (C17)](../architecture/ADR-005-tracing-context.md#83-background-job-tracing-strategy-c17-resolution) and [ADR-013 §3.6 (C18)](../architecture/ADR-013-reliability-error-handling.md#36-event-tracking-in-background-jobs-c18-resolution) for full architecture.

E11y provides two critical Sidekiq middlewares:

#### 6.1. Trace Middleware (C17: New Trace + Parent Link)

**Problem:** Jobs need NEW trace_id (for bounded duration) but must link to parent request.

**Solution:** `SidekiqTraceMiddleware` creates new trace + stores parent link:

```ruby
# lib/e11y/sidekiq/trace_middleware.rb
module E11y
  module Sidekiq
    class TraceMiddleware
      def call(worker, job, queue)
        # Extract parent trace from job metadata
        parent_trace_id = job['e11y_parent_trace_id']
        
        # Start NEW trace for this job
        new_trace_id = E11y::TraceContext.generate_trace_id
        
        # Set trace context for job execution
        E11y::TraceContext.with_trace(
          trace_id: new_trace_id,
          parent_trace_id: parent_trace_id  # ✅ Link to parent!
        ) do
          yield  # Execute job
        end
      end
    end
  end
end

# Configuration (automatic in E11y):
::Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add E11y::Sidekiq::TraceMiddleware
  end
end

# Usage (automatic):
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    # Current context:
    # - trace_id: xyz-789 (NEW trace for job)
    # - parent_trace_id: abc-123 (link to parent request)
    
    Events::OrderProcessing.track(order_id: order_id)
    # Event metadata automatically includes:
    # - trace_id: xyz-789
    # - parent_trace_id: abc-123
  end
end

# When enqueuing from request:
E11y::TraceContext.with_trace(trace_id: 'abc-123') do
  ProcessOrderJob.perform_later(order.id)
  # Job metadata: { e11y_parent_trace_id: 'abc-123' }
end
```

**Benefits:**
- ✅ **Bounded traces:** Job traces don't inflate request SLO metrics
- ✅ **Full visibility:** Query `{trace_id="abc-123"} OR {parent_trace_id="abc-123"}` sees request + jobs
- ✅ **SLO accuracy:** Request P99 (200ms) ≠ Job P99 (5 minutes)

---

#### 6.2. Error Handling Middleware (C18: Non-Failing Event Tracking)

**Problem:** If E11y event tracking fails, background job should NOT fail (business logic > observability).

**Solution:** `SidekiqErrorHandlingMiddleware` rescues E11y failures:

```ruby
# lib/e11y/sidekiq/error_handling_middleware.rb
module E11y
  module Sidekiq
    class ErrorHandlingMiddleware
      def call(worker, job, queue)
        yield  # Execute job
      rescue => error
        # Job business logic failed → let Sidekiq handle it
        raise
      ensure
        # ✅ Wrap E11y tracking in rescue block
        begin
          # Track job completion (success or failure)
          track_job_completion(worker, job, error)
        rescue => e11y_error
          # ⚠️ E11y tracking failed, but DON'T fail the job!
          E11y.logger.error "E11y tracking failed: #{e11y_error.message}"
          
          # Send to DLQ for later analysis (optional)
          E11y::DeadLetterQueue.save({
            event_name: 'e11y.tracking_failed',
            job_class: worker.class.name,
            job_id: job['jid'],
            error: e11y_error.message
          })
        end
      end
      
      private
      
      def track_job_completion(worker, job, error)
        if error
          Events::JobFailed.track(
            job_class: worker.class.name,
            job_id: job['jid'],
            error_class: error.class.name,
            error_message: error.message
          )
        else
          Events::JobSucceeded.track(
            job_class: worker.class.name,
            job_id: job['jid'],
            duration_ms: job_duration(job)
          )
        end
      end
    end
  end
end

# Configuration (automatic in E11y):
::Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add E11y::Sidekiq::ErrorHandlingMiddleware
  end
end

# Configuration (explicit control):
E11y.configure do |config|
  config.error_handling do
    # ✅ Don't fail jobs on E11y errors
    fail_on_error_in_jobs false  # Default: false
    
    # Send failed tracking to DLQ
    send_tracking_failures_to_dlq true
  end
end
```

**Example Scenario:**

```ruby
class ProcessPaymentJob < ApplicationJob
  def perform(order_id)
    # 1. Business logic (MUST succeed!)
    payment = Payment.create!(order_id: order_id, amount: 99.99)
    Stripe.charge(payment)
    
    # 2. E11y tracking (NICE to have, but not critical)
    Events::PaymentProcessed.track(order_id: order_id, amount: 99.99)
    # ⚠️ If this fails (Loki down, network timeout):
    # - Error caught by ErrorHandlingMiddleware
    # - Logged to E11y.logger
    # - Saved to DLQ (for replay later)
    # - Job STILL SUCCEEDS! ✅
    # - Payment was created and charged successfully
  end
end

# Timeline (when E11y tracking fails):
# 10:00:00 Job started
# 10:00:01 Payment created (SUCCESS ✅)
# 10:00:02 Stripe charged (SUCCESS ✅)
# 10:00:03 E11y tracking failed (Loki timeout ❌)
#   → Error caught by middleware
#   → Event saved to DLQ
#   → Job marked as SUCCESS ✅ (business logic succeeded!)
# 10:00:04 Job completed successfully

# Later (when Loki is back online):
# Replay DLQ → Failed event tracked retroactively
```

**Trade-offs:**

| Aspect | Pro | Con | Decision |
|--------|-----|-----|----------|
| **fail_on_error: false** | Business logic always succeeds | Silent E11y failures | Business logic > observability |
| **DLQ for failed tracking** | Can replay events later | DLQ overhead | Worth it for critical events |
| **Error logging** | Visibility into E11y issues | Log noise if Loki down | Logged at ERROR level (not spam) |

**Why this matters:**

```ruby
# ❌ BAD: E11y failure fails the job
config.error_handling_fail_on_error_in_jobs = true

# Job fails if Loki is down:
# - Payment was created successfully
# - Stripe was charged successfully
# - BUT: Job retried because E11y tracking failed!
# - Result: Duplicate payments! 💸💸💸

# ✅ GOOD: E11y failure doesn't fail the job
config.error_handling_fail_on_error_in_jobs = false

# Job succeeds even if Loki is down:
# - Payment created ✅
# - Stripe charged ✅
# - E11y tracking saved to DLQ (replay later)
# - Job marked as successful ✅
# - No duplicate payments!
```

---

## 🔧 Configuration

### Full configuration (shipped API)

There is **no** `config.background_jobs` / `sidekiq do` / `active_job do` DSL in the gem. Use boolean flags and the standard error-handling attribute:

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.rails_instrumentation_enabled = true # ActiveJob ASN events when using Rails adapter

  config.sidekiq_enabled = true    # Sidekiq client + server middleware
  config.active_job_enabled = true # ActiveJob::Base (+ ApplicationJob if defined) callbacks

  config.ephemeral_buffer_enabled = true
  # config.ephemeral_buffer_job_buffer_limit = 500 # optional

  # Job must not fail because E11y could not ship an event (see error-handling docs)
  # config.error_handling_fail_on_error = true # default; tune per app if needed
end
```

Details: [RAILS_INTEGRATION.md](../RAILS_INTEGRATION.md), `lib/e11y/instruments/sidekiq.rb`, `lib/e11y/instruments/active_job.rb`.

---

## 📊 Metrics

**Automatic metrics from job tracking:**
```ruby
# === JOB EXECUTION ===
jobs_enqueued_total{job,queue}                    # Jobs added to queue
jobs_started_total{job,queue}                     # Jobs picked up by worker
jobs_processed_total{job,queue,status}            # Jobs completed (status: success/failed)
jobs_duration_seconds{job,queue}                  # Job execution time (histogram)
jobs_latency_seconds{job,queue}                   # Time in queue before execution

# === RETRIES ===
jobs_retried_total{job,queue,attempt}             # Retry attempts
jobs_retry_exhausted_total{job,queue}             # Jobs that exhausted retries

# === QUEUE HEALTH ===
jobs_queue_size{queue}                            # Current queue depth
jobs_queue_latency_seconds{queue}                 # Oldest job waiting time
jobs_working{queue}                               # Jobs currently processing

# === SUCCESS RATES ===
jobs_success_rate{job,queue}                      # Success / (Success + Failed)

# Prometheus queries:
# - Job success rate:
#   sum(rate(jobs_processed_total{status="success"}[5m])) / sum(rate(jobs_processed_total[5m]))
#
# - p95 job duration:
#   histogram_quantile(0.95, rate(jobs_duration_seconds_bucket[5m]))
#
# - Queue backlog:
#   jobs_queue_size > 1000
```

---

## 🧪 Testing

```ruby
# spec/jobs/send_email_job_spec.rb
RSpec.describe SendEmailJob do
  include ActiveJob::TestHelper
  
  it 'tracks job execution' do
    user = create(:user)
    
    # Track enqueue event
    expect {
      SendEmailJob.perform_later(user.id)
    }.to track_event('job.enqueued').with(
      job_class: 'SendEmailJob',
      queue: 'mailers'
    )
    
    # Execute job
    perform_enqueued_jobs
    
    # Verify events tracked
    events = E11y::Buffer.flush
    expect(events.map(&:event_name)).to include(
      'job.started',
      'email.sent',
      'job.succeeded'
    )
    
    # Verify all events share same trace_id
    trace_ids = events.map { |e| e[:trace_id] }.uniq
    expect(trace_ids.size).to eq(1)
  end
  
  it 'tracks job retries' do
    user = create(:user)
    
    # Simulate failure
    allow(UserMailer).to receive(:welcome).and_raise(Net::SMTPServerBusy)
    
    # Perform (will fail and retry)
    perform_enqueued_jobs
    
    # Verify retry event
    events = E11y::Buffer.flush
    expect(events.map(&:event_name)).to include('job.failed', 'job.retried')
    
    retry_event = events.find { |e| e[:event_name] == 'job.retried' }
    expect(retry_event[:payload][:attempt]).to eq(2)
  end
end

# RSpec matcher (custom)
RSpec::Matchers.define :track_event do |event_name|
  match do |block|
    before_count = E11y::Buffer.size
    block.call
    after_count = E11y::Buffer.size
    
    new_events = E11y::Buffer.pop(after_count - before_count)
    @tracked_event = new_events.find { |e| e[:event_name] == event_name }
    
    @tracked_event.present?
  end
  
  chain :with do |expected_payload|
    @expected_payload = expected_payload
  end
  
  match_when_negated do |block|
    !@tracked_event
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Let E11y auto-track job lifecycle**
```ruby
# ✅ GOOD: Auto-tracking handles basics
class MyJob < ApplicationJob
  def perform(data)
    # Job lifecycle tracked automatically
    process(data)
  end
end
```

**2. Add custom events for business logic**
```ruby
# ✅ GOOD: Track important business steps
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    Events::InventoryChecked.track(...)
    Events::PaymentCaptured.track(...)
    Events::ShipmentScheduled.track(...)
  end
end
```

**3. Monitor queue health**
```ruby
# ✅ GOOD: Alert on queue issues
# Alert: jobs_queue_size{queue="critical"} > 100
# Alert: jobs_queue_latency_seconds > 60
```

---

### ❌ DON'T

**1. Don't manually track job start/end**
```ruby
# ❌ BAD: Redundant (auto-tracked!)
class MyJob < ApplicationJob
  def perform(data)
    Events::JobStarted.track(...)  # ← E11y does this!
    process(data)
    Events::JobEnded.track(...)    # ← E11y does this!
  end
end

# ✅ GOOD: Let E11y handle it
class MyJob < ApplicationJob
  def perform(data)
    process(data)  # That's it!
  end
end
```

**2. Don't ignore retry signals**
```ruby
# ❌ BAD: Silent retries
class MyJob < ApplicationJob
  def perform(data)
    process(data)
  rescue => e
    # Swallowing error = no retry!
  end
end

# ✅ GOOD: Let errors bubble up
class MyJob < ApplicationJob
  retry_on ApiError, wait: 5.seconds
  
  def perform(data)
    process(data)  # Error bubbles up → auto retry
  end
end
```

---

## 📚 Related Use Cases

- **[UC-006: Trace Context Management](./UC-006-trace-context-management.md)** - Trace propagation
- **[UC-004: Zero-Config SLO Tracking](./UC-004-zero-config-slo-tracking.md)** - Job SLOs

---

## 🎯 Summary

### Zero-Config Benefits

| Feature | Manual Approach | E11y Auto-Tracking |
|---------|----------------|-------------------|
| Job lifecycle | 50 lines/job | 0 lines (automatic!) |
| Trace correlation | Complex middleware | Automatic |
| Retry tracking | Manual counters | Automatic |
| Queue metrics | External gem | Built-in |
| SLO tracking | Custom code | Automatic |

**Developer Experience:**
- ❌ Before: 50+ lines tracking code per job
- ✅ After: 0 lines (fully automatic!)
- **Time saved:** 30 min per job → 0 min

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete
