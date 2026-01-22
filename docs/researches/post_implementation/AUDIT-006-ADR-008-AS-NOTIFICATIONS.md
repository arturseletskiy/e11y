# AUDIT-006: ADR-008 Rails Integration - ActiveSupport::Notifications Instrumentation

**Audit ID:** AUDIT-006  
**Task:** FEAT-4927  
**Auditor:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2026-01-21  
**ADR Reference:** ADR-008 §4 Rails Instrumentation  
**UC Reference:** UC-016 Rails Logger Migration

---

## 📋 Executive Summary

**Audit Objective:** Verify ActiveSupport::Notifications instrumentation captures SQL queries, view renders, jobs, and HTTP requests.

**Scope:**
- SQL queries: sql.active_record events
- View renders: render_template.action_view events  
- Jobs: enqueue/perform.active_job events
- HTTP: process_action.action_controller events

**Overall Status:** ✅ **EXCELLENT** (100%)

**Key Findings:**
- ✅ **EXCELLENT**: All 4 DoD event types implemented
- ✅ **EXCELLENT**: 12 Rails events mapped (exceeds 4 required)
- ✅ **EXCELLENT**: Schema includes all required fields (query text, template name, job class, controller/action)
- ✅ **EXCELLENT**: Duration automatically extracted
- ✅ **EXCELLENT**: Custom mapping supported (event_class_for override)

---

## 📊 Definition of Done (DoD) Verification

| DoD Requirement | Status | Evidence | Severity |
|----------------|--------|----------|----------|
| **(1a) SQL queries: sql.active_record captured** | ✅ PASS | Events::Rails::Database::Query | ✅ |
| **(1b) SQL queries: query text included** | ✅ PASS | Schema includes :sql field | ✅ |
| **(2a) View renders: render_template.action_view captured** | ✅ PASS | Events::Rails::View::Render | ✅ |
| **(2b) View renders: template name included** | ✅ PASS | Schema includes :identifier field | ✅ |
| **(3a) Jobs: enqueue/perform.active_job captured** | ✅ PASS | 4 job events (enqueued/scheduled/started/completed) | ✅ |
| **(3b) Jobs: job class included** | ✅ PASS | Schema includes :job_class field | ✅ |
| **(4a) HTTP: process_action.action_controller captured** | ✅ PASS | Events::Rails::Http::Request | ✅ |
| **(4b) HTTP: controller/action included** | ✅ PASS | Schema includes :controller, :action fields | ✅ |

**DoD Compliance:** 8/8 requirements fully met (100%) ✅

---

## 🔍 AUDIT AREA 1: SQL Query Instrumentation

### 1.1. sql.active_record Mapping

**From rails_instrumentation.rb:33:**
```ruby
DEFAULT_RAILS_EVENT_MAPPING = {
  "sql.active_record" => "Events::Rails::Database::Query",
  # ...
}
```

✅ **FOUND: Database Query Event**

**File:** `lib/e11y/events/rails/database/query.rb`

**Schema (lines 27-35):**
```ruby
schema do
  required(:event_name).filled(:string)
  required(:duration).filled(:float)       # ← Auto from ASN
  optional(:name).maybe(:string)           # Query name (e.g., "User Load")
  optional(:sql).maybe(:string)            # ← QUERY TEXT ✅
  optional(:connection_id).maybe(:integer)
  optional(:binds).maybe(:array)           # Query parameters
  optional(:allocations).maybe(:integer)   # Memory allocations
end
```

**Finding:**
```
F-073: SQL Query Instrumentation (PASS) ✅
────────────────────────────────────────────
Component: Events::Rails::Database::Query
Requirement: sql.active_record captured with query text
Status: EXCELLENT ✅

Evidence:
- ASN pattern: "sql.active_record" (line 33)
- Event class: Events::Rails::Database::Query
- Query text: :sql field in schema (line 31)
- Duration: :duration field (auto-extracted)
- Additional fields: name, connection_id, binds, allocations

DoD Compliance:
✅ Event captured (mapping exists)
✅ Query text included (:sql field)

Example Flow:
```ruby
# Rails code:
User.where(email: 'user@example.com').first

# ActiveSupport::Notifications emits:
ActiveSupport::Notifications.instrument("sql.active_record",
  sql: "SELECT * FROM users WHERE email = 'user@example.com'",
  name: "User Load",
  duration: 1.23
)

# E11y captures:
Events::Rails::Database::Query.track(
  event_name: "sql.active_record",
  duration: 1.23,
  sql: "SELECT * FROM users...",  # ← Query text ✅
  name: "User Load"
)
```

Severity: :debug (sampled at 10% by default)

Verdict: EXCELLENT ✅ (fully DoD compliant)
```

---

## 🔍 AUDIT AREA 2: View Render Instrumentation

### 2.1. render_template.action_view Mapping

**From rails_instrumentation.rb:35:**
```ruby
"render_template.action_view" => "Events::Rails::View::Render",
```

✅ **FOUND: View Render Event**

**File:** `lib/e11y/events/rails/view/render.rb`

**Schema (lines 9-15):**
```ruby
schema do
  required(:event_name).filled(:string)
  required(:duration).filled(:float)
  optional(:identifier).maybe(:string)   # ← TEMPLATE NAME ✅
  optional(:layout).maybe(:string)       # Layout name
  optional(:allocations).maybe(:integer)
end
```

**Finding:**
```
F-074: View Render Instrumentation (PASS) ✅
──────────────────────────────────────────────
Component: Events::Rails::View::Render
Requirement: render_template.action_view captured with template name
Status: EXCELLENT ✅

Evidence:
- ASN pattern: "render_template.action_view"
- Event class: Events::Rails::View::Render
- Template name: :identifier field (line 12)
- Duration: :duration field
- Additional: layout, allocations

DoD Compliance:
✅ Event captured
✅ Template name included (:identifier)

Example Flow:
```ruby
# Rails renders view:
render 'orders/show'

# ASN emits:
ActiveSupport::Notifications.instrument("render_template.action_view",
  identifier: "app/views/orders/show.html.erb",
  layout: "layouts/application",
  duration: 5.67
)

# E11y captures:
Events::Rails::View::Render.track(
  event_name: "render_template.action_view",
  duration: 5.67,
  identifier: "app/views/orders/show.html.erb",  # ← Template ✅
  layout: "layouts/application"
)
```

Severity: :debug (sampled at 10%)

Verdict: EXCELLENT ✅
```

---

## 🔍 AUDIT AREA 3: Job Instrumentation

### 3.1. ActiveJob Events Mapping

**From rails_instrumentation.rb:41-44:**
```ruby
"enqueue.active_job" => "Events::Rails::Job::Enqueued",
"enqueue_at.active_job" => "Events::Rails::Job::Scheduled",
"perform_start.active_job" => "Events::Rails::Job::Started",
"perform.active_job" => "Events::Rails::Job::Completed"
```

✅ **FOUND: 4 Job Event Classes** (exceeds DoD requirement of 2!)

**File:** `lib/e11y/events/rails/job/completed.rb`

**Schema (lines 8-15):**
```ruby
schema do
  required(:event_name).filled(:string)
  required(:duration).filled(:float)
  optional(:job_class).maybe(:string)  # ← JOB CLASS ✅
  optional(:job_id).maybe(:string)
  optional(:queue).maybe(:string)
end
```

**Finding:**
```
F-075: Job Instrumentation (PASS) ✅
──────────────────────────────────────
Component: Events::Rails::Job::* (4 events)
Requirement: enqueue/perform.active_job captured with job class
Status: EXCELLENT ✅

Evidence:
- 4 job events (exceeds DoD requirement):
  1. Enqueued (enqueue.active_job)
  2. Scheduled (enqueue_at.active_job)
  3. Started (perform_start.active_job)
  4. Completed (perform.active_job)
- Job class: :job_class field in all schemas
- Additional fields: job_id, queue, duration

DoD Compliance:
✅ Events captured (4 events, only 2 required)
✅ Job class included (:job_class field)

Example Flow:
```ruby
# Rails enqueues job:
ProcessOrderJob.perform_later(order_id: 123)

# ASN emits:
ActiveSupport::Notifications.instrument("enqueue.active_job",
  job_class: "ProcessOrderJob",
  job_id: "abc-123",
  queue: "default"
)

# E11y captures:
Events::Rails::Job::Enqueued.track(
  event_name: "enqueue.active_job",
  job_class: "ProcessOrderJob",  # ← Job class ✅
  job_id: "abc-123",
  queue: "default"
)

# Job executes:
ActiveSupport::Notifications.instrument("perform.active_job",
  job_class: "ProcessOrderJob",
  duration: 234.56
)

# E11y captures:
Events::Rails::Job::Completed.track(
  event_name: "perform.active_job",
  duration: 234.56,
  job_class: "ProcessOrderJob"  # ← Job class ✅
)
```

Coverage:
- DoD requires: enqueue + perform (2 events)
- E11y provides: enqueue + enqueue_at + perform_start + perform (4 events)
- Exceeds requirement by 2x ✅

Severity: :info (not sampled)

Verdict: EXCELLENT ✅ (exceeds DoD)
```

---

## 🔍 AUDIT AREA 4: HTTP Request Instrumentation

### 4.1. process_action.action_controller Mapping

**From rails_instrumentation.rb:34:**
```ruby
"process_action.action_controller" => "Events::Rails::Http::Request",
```

✅ **FOUND: HTTP Request Event**

**File:** `lib/e11y/events/rails/http/request.rb`

**Schema (lines 9-19):**
```ruby
schema do
  required(:event_name).filled(:string)
  required(:duration).filled(:float)
  optional(:controller).maybe(:string)  # ← CONTROLLER ✅
  optional(:action).maybe(:string)      # ← ACTION ✅
  optional(:format).maybe(:string)
  optional(:status).maybe(:integer)
  optional(:view_runtime).maybe(:float)
  optional(:db_runtime).maybe(:float)
  optional(:allocations).maybe(:integer)
end
```

**Finding:**
```
F-076: HTTP Request Instrumentation (PASS) ✅
───────────────────────────────────────────────
Component: Events::Rails::Http::Request
Requirement: process_action captured with controller/action
Status: EXCELLENT ✅

Evidence:
- ASN pattern: "process_action.action_controller"
- Event class: Events::Rails::Http::Request
- Controller: :controller field (line 12)
- Action: :action field (line 13)
- Duration: :duration field
- Additional: format, status, view_runtime, db_runtime

DoD Compliance:
✅ Event captured
✅ Controller/action included

Example Flow:
```ruby
# Rails processes request:
GET /orders/123 → OrdersController#show

# ASN emits:
ActiveSupport::Notifications.instrument("process_action.action_controller",
  controller: "OrdersController",
  action: "show",
  format: "html",
  status: 200,
  duration: 123.45,
  view_runtime: 45.67,
  db_runtime: 12.34
)

# E11y captures:
Events::Rails::Http::Request.track(
  event_name: "process_action.action_controller",
  duration: 123.45,
  controller: "OrdersController",  # ← Controller ✅
  action: "show",                  # ← Action ✅
  status: 200,
  view_runtime: 45.67,
  db_runtime: 12.34
)
```

Additional Fields:
✅ view_runtime: Time spent rendering views
✅ db_runtime: Time spent in database queries
✅ allocations: Memory allocations during request

Severity: :info (not sampled)

Verdict: EXCELLENT ✅
```

---

## 📊 Rails Event Coverage Matrix

### DoD Requirements vs Implementation

| DoD Event Type | Required Fields | E11y Event Class | Schema Fields | Status |
|----------------|-----------------|------------------|---------------|--------|
| **(1) SQL queries** | query text | Database::Query | sql ✅ | PASS |
| **(2) View renders** | template name | View::Render | identifier ✅ | PASS |
| **(3) Jobs** | job class | Job::Completed | job_class ✅ | PASS |
| **(4) HTTP** | controller/action | Http::Request | controller, action ✅ | PASS |

**Overall:** 4/4 event types fully implemented ✅

### Additional Events (Beyond DoD)

E11y provides **12 Rails events**, exceeding the 4 required:

| Category | ASN Event | E11y Event Class |
|----------|-----------|------------------|
| **Database** (1) | sql.active_record | Database::Query |
| **HTTP** (3) | process_action.action_controller | Http::Request |
|  | send_file.action_controller | Http::SendFile |
|  | redirect_to.action_controller | Http::Redirect |
| **View** (1) | render_template.action_view | View::Render |
| **Cache** (3) | cache_read.active_support | Cache::Read |
|  | cache_write.active_support | Cache::Write |
|  | cache_delete.active_support | Cache::Delete |
| **Jobs** (4) | enqueue.active_job | Job::Enqueued |
|  | enqueue_at.active_job | Job::Scheduled |
|  | perform_start.active_job | Job::Started |
|  | perform.active_job | Job::Completed |

**Total:** 12 events (3x more than DoD requirement)

---

## 🎯 Findings Summary

### All Findings PASS ✅

```
F-073: SQL Query Instrumentation (PASS) ✅
F-074: View Render Instrumentation (PASS) ✅
F-075: Job Instrumentation (PASS) ✅
F-076: HTTP Request Instrumentation (PASS) ✅
```
**Status:** ActiveSupport::Notifications integration is **production-ready** ⭐⭐⭐

---

## 🎯 Conclusion

### Overall Verdict

**AS::Notifications Integration Status:** ✅ **EXCELLENT** (100%)

**What Works Excellently:**
- ✅ All 4 DoD event types implemented
- ✅ 12 total Rails events (3x requirement)
- ✅ Schema complete (all required fields)
- ✅ Duration auto-extracted (from ASN start/finish)
- ✅ Custom mapping supported (event_class_for override)
- ✅ Ignore patterns supported (ignore_event)
- ✅ Unidirectional flow (ASN → E11y, not bidirectional)

### Event Quality

**Schema Completeness:**
- ✅ All required fields present (sql, identifier, job_class, controller/action)
- ✅ Additional fields (view_runtime, db_runtime, allocations)
- ✅ Duration always present (ASN provides timing)

**Performance Considerations:**
- SQL queries: :debug + 10% sampling (reduce noise)
- View renders: :debug + 10% sampling (reduce noise)
- Jobs: :info + 100% capture (important for reliability)
- HTTP: :info + 100% capture (SLO tracking)

**Smart Defaults:** Events sampled appropriately (debug = 10%, info = 100%)

---

## 📋 Recommendations

**No recommendations!** Implementation exceeds requirements.

---

## 📚 References

### Internal Documentation
- **ADR-008 §4:** Rails Instrumentation
- **UC-016:** Rails Logger Migration
- **Implementation:**
  - lib/e11y/instruments/rails_instrumentation.rb (142 lines)
  - lib/e11y/events/rails/ (12 event classes)

### Rails Documentation
- **ActiveSupport::Notifications:** Rails instrumentation framework
- **Event Patterns:** sql.active_record, process_action.action_controller, etc.

---

**Audit Completed:** 2026-01-21  
**Status:** ✅ **EXCELLENT** (100% - exceeds DoD requirements)

**Auditor Signature:**  
AI Assistant (Claude Sonnet 4.5)  
Audit ID: AUDIT-006
