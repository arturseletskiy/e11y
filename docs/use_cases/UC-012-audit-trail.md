# UC-012: Audit Trail (Compliance-Ready)

**Status:** v1.0 Feature (Critical for Compliance)  
**Complexity:** Advanced  
**Setup Time:** 30-45 minutes  
**Target Users:** Security Teams, Compliance Officers, Auditors, Backend Developers

---

## 📋 Overview

### Problem Statement

**The $2M GDPR fine:**
```ruby
# ❌ NO AUDIT TRAIL: Can't prove what happened
class UsersController < ApplicationController
  def destroy
    user = User.find(params[:id])
    user.destroy  # WHO deleted this? WHEN? WHY?
    
    # Regular log (not audit-ready):
    Rails.logger.info "User #{user.id} deleted"
    
    # Problems:
    # - No WHO (which admin deleted it?)
    # - No WHY (reason for deletion?)
    # - No immutability (logs can be edited)
    # - No retention guarantee (logs may be rotated out)
    # - No cryptographic proof (can't prove authenticity)
    # - GDPR violation: Can't prove "right to be forgotten" compliance
end

# Result: $2M GDPR fine for lack of audit trail 😱
```

**Real-world compliance requirements:**
- **GDPR**: Must prove data deletion on request
- **HIPAA**: Must track all access to patient data
- **SOX**: Must audit financial transactions
- **ISO 27001**: Must maintain security event logs
- **PCI DSS**: Must track all access to cardholder data

### E11y Solution

**Immutable, cryptographically-signed audit trail:**
```ruby
# ✅ AUDIT TRAIL: Compliance-ready
class UsersController < ApplicationController
  def destroy
    user = User.find(params[:id])
    
    # Audit trail (immutable, signed)
    Events::UserDeleted.audit(
      user_id: user.id,
      user_email: user.email,  # Captured before deletion
      deleted_by: current_user.id,
      deleted_by_email: current_user.email,
      reason: params[:reason],
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      compliance_basis: 'gdpr_right_to_be_forgotten',
      retention_period: 7.years  # Legal requirement
    )
    
    user.destroy
    
    render json: { status: 'deleted' }
  end
end

# Result:
# ✅ Immutable audit record (can't be altered)
# ✅ Cryptographically signed (authenticity proof)
# ✅ Separate storage (can't be deleted with app DB)
# ✅ Long retention (7 years for GDPR)
# ✅ Searchable (find all deletions by admin X)
# ✅ Compliant (ready for auditor review)
```

---

## 🎯 Features

### 1. Audit Event API

**Separate from regular events:**
```ruby
# Regular event (can be sampled, rate-limited, dropped)
Events::OrderPaid.track(order_id: '123', amount: 99)

# Audit event (NEVER sampled/dropped, immutably stored)
Events::OrderPaid.audit(
  order_id: '123',
  amount: 99,
  audited_by: current_user.id,
  audit_reason: 'financial_record'
)
```

**Audit events have special properties:**
- ❌ **Never sampled** - 100% of audit events stored
- ❌ **Never rate-limited** - All audit events tracked
- ❌ **Never dropped** - Guaranteed storage
- ✅ **Immutable** - Can't be modified after creation
- ✅ **Cryptographically signed** - Authenticity proof
- ✅ **Separate storage** - Isolated from regular logs
- ✅ **Long retention** - Configurable (1-10+ years)

---

### 2. Cryptographic Signing

**Every audit event is signed:**
```ruby
E11y.configure do |config|
  config.audit_trail do
    # Enable cryptographic signing
    signing enabled: true,
            algorithm: 'HMAC-SHA256',  # OR 'RSA-SHA256'
            secret_key: ENV['AUDIT_SIGNING_KEY']
    
    # Verify signatures on read
    verify_on_read true
    
    # Alert on signature mismatch
    alert_on_invalid_signature true
  end
end

# How it works:
# 1. Event data serialized to JSON
# 2. HMAC-SHA256 signature computed
# 3. Signature stored with event
# 4. On read: recompute signature, verify match
# 5. If mismatch → event was tampered with!
```

**Signature format:**
```ruby
{
  event_id: 'audit_abc123',
  event_name: 'user.deleted',
  timestamp: '2026-01-12T10:30:00Z',
  payload: { user_id: '456', deleted_by: '789' },
  signature: 'a1b2c3d4e5f6...',  # HMAC-SHA256
  signature_algorithm: 'HMAC-SHA256',
  signed_at: '2026-01-12T10:30:00Z'
}

# Verification:
computed_signature = HMAC.hexdigest('SHA256', secret_key, event_json)
if computed_signature != stored_signature
  raise AuditTrail::TamperDetected, "Event #{event_id} signature invalid!"
end
```

---

### 3. Immutable Storage

**Write-once, read-many:**
```ruby
E11y.configure do |config|
  config.audit_trail do
    # Separate storage for audit events
    storage adapter: :postgresql,  # OR :s3, :file
            table: 'audit_events',
            read_only: true  # Can't UPDATE/DELETE
    
    # S3 with object lock (true immutability)
    # storage adapter: :s3,
    #         bucket: 'company-audit-trail',
    #         object_lock: true,  # WORM (Write Once Read Many)
    #         retention_period: 7.years
  end
end

# PostgreSQL implementation:
CREATE TABLE audit_events (
  id UUID PRIMARY KEY,
  event_name VARCHAR(255) NOT NULL,
  payload JSONB NOT NULL,
  signature VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL,
  -- NO updated_at (immutable!)
  -- NO deleted_at (can't soft delete!)
  
  -- Read-only after insert
  CHECK (created_at IS NOT NULL)
);

-- Revoke UPDATE/DELETE permissions
REVOKE UPDATE, DELETE ON audit_events FROM app_user;
GRANT INSERT, SELECT ON audit_events TO app_user;

-- Only audit admin can read (compliance requirement)
GRANT SELECT ON audit_events TO audit_admin;
```

---

### 4. Audit Context Enrichment

**Automatically capture WHO, WHAT, WHEN, WHERE, WHY:**
```ruby
E11y.configure do |config|
  config.audit_trail do
    # Automatically enrich all audit events
    auto_enrich do
      # WHO (authentication)
      who do
        {
          user_id: Current.user&.id,
          user_email: Current.user&.email,
          user_role: Current.user&.role,
          impersonating: Current.impersonator&.id  # Admin acting as user
        }
      end
      
      # WHEN (timestamp)
      when do
        {
          timestamp: Time.current,
          timezone: Time.zone.name,
          server_time: Time.now.utc
        }
      end
      
      # WHERE (source)
      where do
        {
          ip_address: Current.request_ip,
          user_agent: Current.user_agent,
          hostname: Socket.gethostname,
          service: ENV['SERVICE_NAME'],
          deployment_id: ENV['DEPLOYMENT_ID']
        }
      end
      
      # WHAT (action context)
      what do
        {
          controller: Current.controller_name,
          action: Current.action_name,
          request_id: Current.request_id,
          trace_id: E11y::TraceId.current
        }
      end
      
      # WHY (reason - from event payload)
      # Extracted from event.payload[:audit_reason]
    end
  end
end

# Usage (minimal code):
Events::UserDeleted.audit(
  user_id: user.id,
  audit_reason: 'gdpr_request'
  # WHO, WHEN, WHERE, WHAT automatically added!
)

# Result:
# {
#   event_name: 'user.deleted',
#   payload: { user_id: '456', audit_reason: 'gdpr_request' },
#   who: { user_id: '789', user_email: 'admin@company.com', user_role: 'admin' },
#   when: { timestamp: '2026-01-12T10:30:00Z', timezone: 'UTC' },
#   where: { ip_address: '192.168.1.1', hostname: 'app-01' },
#   what: { controller: 'users', action: 'destroy', request_id: 'abc-123' },
#   signature: 'a1b2c3...'
# }
```

---

### 5. Retention Policies

**Configure retention per event type:**
```ruby
E11y.configure do |config|
  config.audit_trail do
    # === LEGAL REQUIREMENTS ===
    
    # GDPR: Data deletion records (7 years)
    retention_for event_pattern: 'user.deleted',
                  duration: 7.years,
                  reason: 'gdpr_article_30'
    
    # HIPAA: Patient data access (6 years)
    retention_for event_pattern: 'patient.accessed',
                  duration: 6.years,
                  reason: 'hipaa_164.316'
    
    # SOX: Financial transactions (7 years)
    retention_for event_pattern: 'transaction.*',
                  duration: 7.years,
                  reason: 'sox_section_802'
    
    # PCI DSS: Payment data (1 year)
    retention_for event_pattern: 'payment.*',
                  duration: 1.year,
                  reason: 'pci_dss_10.7'
    
    # === DEFAULT ===
    default_retention 3.years
    
    # === ARCHIVAL ===
    archive_after 1.year,
                  to: :s3_glacier,  # Cheaper cold storage
                  bucket: 'company-audit-archive'
  end
end

# How it works:
# 1. Events stored in hot storage (PostgreSQL/S3)
# 2. After 1 year → moved to cold storage (Glacier)
# 3. After retention period → permanently deleted
# 4. Deletion logged as audit event (audit the audit!)
```

---

## 🏗️ Event Class Configuration

**IMPORTANT:** All audit configuration is defined in the event class, NOT at call-time!

```ruby
# ✅ CORRECT: Configuration in event class
module Events
  class GdprDeletionRequested < E11y::AuditEvent
    # Audit configuration (defined once!)
    audit_retention 7.years          # How long to keep
    audit_reason 'gdpr_article_17'   # Why it's audited
    severity :warn                    # Default severity
    
    # Schema (validates payload)
    schema do
      required(:user_id).filled(:string)
      required(:reason).filled(:string)
    end
  end
end

# Usage: Clean, no duplication!
Events::GdprDeletionRequested.audit(
  user_id: user.id,
  reason: 'user_request'
  # ← No retention_period, audit_reason, severity!
)

# ❌ WRONG: Configuration at call-time (DON'T DO THIS!)
Events::GdprDeletionRequested.audit(
  user_id: user.id,
  reason: 'user_request',
  retention_period: 7.years,  # ← WRONG! Belongs in class
  audit_reason: 'gdpr'         # ← WRONG! Belongs in class
)
```

### Available Event Configuration DSL

```ruby
module Events
  class MyAuditEvent < E11y::AuditEvent
    # === AUDIT-SPECIFIC ===
    audit_retention 7.years              # Retention period
    audit_reason 'compliance_reason'     # Audit justification
    
    # === SIGNING ===
    signing enabled: true,               # Enable cryptographic signing
            algorithm: 'HMAC-SHA256'     # OR 'RSA-SHA256'
    
    # === STANDARD EVENT CONFIG ===
    severity :warn                       # Default severity
    
    # === SCHEMA ===
    schema do
      required(:field).filled(:string)
    end
    
    # === METRICS (optional) ===
    metric :counter, name: 'audit.events.total', tags: [:event_type]
  end
end
```

---

## 💻 Implementation Examples

### Example 1: User Data Deletion (GDPR)

```ruby
# app/events/gdpr_deletion_requested.rb
module Events
  class GdprDeletionRequested < E11y::AuditEvent
    # Event configuration (defined once!)
    audit_retention 7.years  # GDPR legal requirement
    audit_reason 'gdpr_article_17_right_to_be_forgotten'
    
    schema do
      required(:user_id).filled(:string)
      required(:user_email).filled(:string)
      required(:user_name).filled(:string)
      required(:user_created_at).filled(:time)
      required(:requested_by).filled(:string)
      required(:reason).filled(:string)
      required(:data_categories).array(:string)
    end
  end
end

# app/events/gdpr_deletion_completed.rb
module Events
  class GdprDeletionCompleted < E11y::AuditEvent
    audit_retention 7.years
    audit_reason 'gdpr_article_17_compliance'
    
    schema do
      required(:user_id).filled(:string)
      required(:deleted_at).filled(:time)
      required(:deleted_by).filled(:string)
      required(:data_categories_deleted).array(:string)
    end
  end
end

# app/services/gdpr_deletion_service.rb
class GdprDeletionService
  def call(user_id:, requested_by:, reason:)
    user = User.find(user_id)
    
    # 1. Audit BEFORE deletion (capture data)
    Events::GdprDeletionRequested.audit(
      user_id: user.id,
      user_email: user.email,
      user_name: user.name,
      user_created_at: user.created_at,
      requested_by: requested_by,
      reason: reason,
      data_categories: ['profile', 'orders', 'payments']
      # ← No retention_period, audit_reason - defined in class!
    )
    
    # 2. Delete user data
    user.orders.destroy_all
    user.payments.destroy_all
    user.destroy
    
    # 3. Audit AFTER deletion (confirmation)
    Events::GdprDeletionCompleted.audit(
      user_id: user.id,
      deleted_at: Time.current,
      deleted_by: requested_by,
      data_categories_deleted: ['profile', 'orders', 'payments']
      # ← No retention_period, audit_reason - defined in class!
    )
    
    # 4. Generate compliance report
    generate_compliance_report(user_id)
  end
  
  private
  
  def generate_compliance_report(user_id)
    # Query audit trail for this user
    deletions = E11y::AuditTrail.query(
      event_name: 'gdpr.deletion.*',
      payload: { user_id: user_id }
    )
    
    # Generate PDF report for auditor
    AuditReportPdf.generate(deletions)
  end
end

# Result:
# ✅ Immutable proof of deletion
# ✅ WHO requested (admin or user)
# ✅ WHEN deleted (timestamp)
# ✅ WHAT deleted (data categories)
# ✅ WHY deleted (GDPR Article 17)
# ✅ Auditor can verify compliance
```

---

### Example 2: Financial Transaction Audit (SOX)

```ruby
# app/events/payment_initiated.rb
module Events
  class PaymentInitiated < E11y::AuditEvent
    audit_retention 7.years  # SOX requirement
    audit_reason 'sox_financial_transaction'
    
    schema do
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:currency).filled(:string)
      required(:payment_method).filled(:string)
      required(:initiated_by).filled(:string)
    end
  end
end

# app/events/payment_succeeded.rb
module Events
  class PaymentSucceeded < E11y::AuditEvent
    audit_retention 7.years
    audit_reason 'sox_financial_transaction'
    
    schema do
      required(:order_id).filled(:string)
      required(:transaction_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:currency).filled(:string)
      optional(:gateway_response).filled(:hash)
      required(:processed_at).filled(:time)
      required(:processed_by).filled(:string)
    end
  end
end

# app/events/payment_failed.rb
module Events
  class PaymentFailed < E11y::AuditEvent
    audit_retention 7.years
    audit_reason 'sox_financial_transaction_failure'
    severity :error  # Default severity for this event
    
    schema do
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:error_code).filled(:string)
      required(:error_message).filled(:string)
      required(:failed_at).filled(:time)
    end
  end
end

# app/services/process_payment_service.rb
class ProcessPaymentService
  def call(order)
    # 1. Audit payment initiation
    Events::PaymentInitiated.audit(
      order_id: order.id,
      amount: order.total,
      currency: order.currency,
      payment_method: order.payment_method,
      initiated_by: Current.user.id
    )
    
    begin
      # 2. Process payment
      result = PaymentGateway.charge(order)
      
      # 3. Audit successful payment
      Events::PaymentSucceeded.audit(
        order_id: order.id,
        transaction_id: result.id,
        amount: order.total,
        currency: order.currency,
        gateway_response: result.raw_response,
        processed_at: Time.current,
        processed_by: Current.user.id
      )
      
      result
    rescue PaymentError => e
      # 4. Audit failed payment (also important!)
      Events::PaymentFailed.audit(
        order_id: order.id,
        amount: order.total,
        error_code: e.code,
        error_message: e.message,
        failed_at: Time.current
      )
      
      raise
    end
  end
end

# Audit query for SOX compliance:
# "Show all financial transactions for Q4 2025"
transactions = E11y::AuditTrail.query(
  event_pattern: 'payment.*',
  time_range: '2025-10-01'..'2025-12-31',
  audit_reason: 'sox_financial_transaction'
)
# → Returns immutable, signed audit records
```

---

### Example 3: Admin Actions Audit

```ruby
# app/events/admin_user_modified.rb
module Events
  class AdminUserModified < E11y::AuditEvent
    audit_retention 3.years
    audit_reason 'admin_modification'
    
    schema do
      required(:user_id).filled(:string)
      required(:modified_by).filled(:string)
      required(:before_state).filled(:hash)
      required(:after_state).filled(:hash)
      required(:changes).filled(:hash)
      required(:justification).filled(:string)  # Required!
    end
  end
end

# app/events/admin_impersonation_started.rb
module Events
  class AdminImpersonationStarted < E11y::AuditEvent
    audit_retention 5.years  # Security event - longer retention
    audit_reason 'security_impersonation'
    severity :warn  # Security events are warnings by default
    
    schema do
      required(:admin_id).filled(:string)
      required(:admin_email).filled(:string)
      required(:target_user_id).filled(:string)
      required(:target_user_email).filled(:string)
      required(:impersonation_reason).filled(:string)
      required(:ip_address).filled(:string)
    end
  end
end

# app/controllers/admin/users_controller.rb
module Admin
  class UsersController < AdminController
    def update
      user = User.find(params[:id])
      
      # Capture BEFORE state
      before_state = user.attributes.slice(
        'email', 'role', 'status', 'verified'
      )
      
      user.update!(user_params)
      
      # Audit admin modification
      Events::AdminUserModified.audit(
        user_id: user.id,
        modified_by: current_admin.id,
        before_state: before_state,
        after_state: user.attributes.slice(
          'email', 'role', 'status', 'verified'
        ),
        changes: user.previous_changes,
        justification: params[:justification]  # Required field
      )
      
      render json: user
    end
    
    def impersonate
      target_user = User.find(params[:user_id])
      
      # Audit impersonation (security-critical!)
      Events::AdminImpersonationStarted.audit(
        admin_id: current_admin.id,
        admin_email: current_admin.email,
        target_user_id: target_user.id,
        target_user_email: target_user.email,
        impersonation_reason: params[:reason],
        ip_address: request.remote_ip
      )
      
      session[:impersonating_user_id] = target_user.id
      session[:impersonator_id] = current_admin.id
      
      redirect_to root_path
    end
  end
end

# Audit query:
# "Show all admin actions for user X"
admin_actions = E11y::AuditTrail.query(
  event_pattern: 'admin.*',
  payload: { user_id: 'user_123' }
)

# "Show all impersonations by admin Y"
impersonations = E11y::AuditTrail.query(
  event_name: 'admin.impersonation.started',
  payload: { admin_id: 'admin_456' }
)
```

---

### Example 4: Data Access Audit (HIPAA)

```ruby
# app/events/patient_data_accessed.rb
module Events
  class PatientDataAccessed < E11y::AuditEvent
    audit_retention 6.years  # HIPAA requirement
    audit_reason 'hipaa_phi_access'
    
    schema do
      required(:patient_id).filled(:string)
      required(:accessed_by).filled(:string)
      required(:accessed_by_role).filled(:string)
      required(:access_type).filled(:string)
      required(:data_fields_accessed).array(:string)
      required(:access_reason).filled(:string)  # Required for HIPAA!
      required(:patient_consented).filled(:bool)
      required(:ip_address).filled(:string)
    end
  end
end

# app/events/patient_data_modified.rb
module Events
  class PatientDataModified < E11y::AuditEvent
    audit_retention 6.years
    audit_reason 'hipaa_phi_modification'
    
    schema do
      required(:patient_id).filled(:string)
      required(:modified_by).filled(:string)
      required(:modified_by_role).filled(:string)
      required(:before_state).filled(:hash)
      required(:after_state).filled(:hash)
      required(:changes).filled(:hash)
      required(:modification_reason).filled(:string)
    end
  end
end

# app/controllers/patients_controller.rb
class PatientsController < ApplicationController
  def show
    patient = Patient.find(params[:id])
    
    # Audit patient data access (HIPAA requirement)
    Events::PatientDataAccessed.audit(
      patient_id: patient.id,
      accessed_by: current_user.id,
      accessed_by_role: current_user.role,  # doctor, nurse, admin
      access_type: 'view',
      data_fields_accessed: ['name', 'dob', 'medical_history'],
      access_reason: params[:reason],  # Required for HIPAA
      patient_consented: patient.consent_given?,
      ip_address: request.remote_ip
    )
    
    render json: patient
  end
  
  def update
    patient = Patient.find(params[:id])
    
    before_state = patient.attributes
    patient.update!(patient_params)
    
    # Audit patient data modification
    Events::PatientDataModified.audit(
      patient_id: patient.id,
      modified_by: current_user.id,
      modified_by_role: current_user.role,
      before_state: before_state,
      after_state: patient.attributes,
      changes: patient.previous_changes,
      modification_reason: params[:reason]
    )
    
    render json: patient
  end
end

# HIPAA audit report:
# "Show all access to patient X in last 90 days"
access_log = E11y::AuditTrail.query(
  event_name: 'patient.data.accessed',
  payload: { patient_id: 'patient_789' },
  time_range: 90.days.ago..Time.current
)
```

---

## 🔍 Audit Trail Query API

**Search and retrieve audit events:**
```ruby
# Query by event name
E11y::AuditTrail.query(
  event_name: 'user.deleted'
)

# Query by pattern
E11y::AuditTrail.query(
  event_pattern: 'admin.*'
)

# Query by payload field
E11y::AuditTrail.query(
  event_name: 'payment.succeeded',
  payload: { order_id: 'order_123' }
)

# Query by time range
E11y::AuditTrail.query(
  event_pattern: 'transaction.*',
  time_range: '2025-01-01'..'2025-12-31'
)

# Query by WHO
E11y::AuditTrail.query(
  event_pattern: '*',
  who: { user_id: 'admin_456' }
)

# Complex query
E11y::AuditTrail.query(
  event_pattern: 'gdpr.*',
  payload: { user_id: 'user_789' },
  time_range: 1.year.ago..Time.current,
  who: { user_role: 'admin' }
)

# Verify signatures
results = E11y::AuditTrail.query(event_name: 'user.deleted')
results.each do |event|
  if event.signature_valid?
    puts "✅ Event #{event.id} signature valid"
  else
    puts "❌ Event #{event.id} TAMPERED!"
  end
end
```

---

## 📊 Compliance Reports

**Generate audit reports for auditors:**
```ruby
# lib/e11y/audit_trail/report_generator.rb
module E11y
  module AuditTrail
    class ReportGenerator
      def generate_gdpr_report(user_id:, output_format: :pdf)
        events = E11y::AuditTrail.query(
          event_pattern: 'gdpr.*',
          payload: { user_id: user_id }
        )
        
        report = {
          user_id: user_id,
          report_generated_at: Time.current,
          total_events: events.count,
          events: events.map do |event|
            {
              event_name: event.event_name,
              timestamp: event.timestamp,
              who: event.who,
              what: event.payload,
              signature_valid: event.signature_valid?
            }
          end
        }
        
        case output_format
        when :pdf
          GdprReportPdf.generate(report)
        when :json
          report.to_json
        when :csv
          GdprReportCsv.generate(report)
        end
      end
      
      def generate_sox_report(quarter:, year:)
        start_date, end_date = calculate_quarter_dates(quarter, year)
        
        events = E11y::AuditTrail.query(
          event_pattern: 'payment.*',
          time_range: start_date..end_date,
          audit_reason: 'sox_financial_transaction'
        )
        
        SoxReportPdf.generate(
          quarter: quarter,
          year: year,
          events: events,
          signatures_valid: events.all?(&:signature_valid?)
        )
      end
      
      def generate_hipaa_access_log(patient_id:, days: 90)
        events = E11y::AuditTrail.query(
          event_name: 'patient.data.accessed',
          payload: { patient_id: patient_id },
          time_range: days.days.ago..Time.current
        )
        
        HipaaAccessLogPdf.generate(
          patient_id: patient_id,
          access_log: events
        )
      end
    end
  end
end

# Usage:
report = E11y::AuditTrail::ReportGenerator.new
pdf = report.generate_gdpr_report(user_id: 'user_123', output_format: :pdf)
# → PDF ready for auditor/regulator
```

---

## 🔒 Security Features

### 1. Tamper Detection

```ruby
# Detect if audit event was modified
event = E11y::AuditTrail.find('audit_abc123')

if event.signature_valid?
  puts "✅ Event authentic"
else
  # CRITICAL: Event was tampered with!
  Events::AuditTamperDetected.audit(
    tampered_event_id: event.id,
    detected_at: Time.current,
    detected_by: 'system',
    severity: :fatal,
    audit_reason: 'security_breach'
  )
  
  # Alert security team
  SecurityAlert.notify(
    type: 'audit_tamper_detected',
    event_id: event.id
  )
end
```

### 2. Access Control

```ruby
# Only specific roles can read audit trail
E11y.configure do |config|
  config.audit_trail do
    # Who can read audit events
    read_access roles: ['auditor', 'compliance_officer', 'security_admin']
    
    # Who can query audit events
    query_access roles: ['auditor', 'compliance_officer']
    
    # Who can export audit reports
    export_access roles: ['compliance_officer']
    
    # Authentication check
    authenticate_with ->(user) {
      user.present? && user.audit_access?
    }
  end
end
```

---

## 🧪 Testing

```ruby
# spec/e11y/audit_trail_spec.rb
RSpec.describe 'E11y Audit Trail' do
  describe 'immutability' do
    it 'prevents modification of audit events' do
      event_id = Events::UserDeleted.audit(user_id: '123')
      
      # Try to modify (should fail)
      expect {
        E11y::AuditTrail.update(event_id, payload: { user_id: '456' })
      }.to raise_error(E11y::AuditTrail::ImmutableError)
    end
  end
  
  describe 'cryptographic signing' do
    it 'signs audit events' do
      event_id = Events::UserDeleted.audit(user_id: '123')
      event = E11y::AuditTrail.find(event_id)
      
      expect(event.signature).to be_present
      expect(event.signature_algorithm).to eq('HMAC-SHA256')
      expect(event.signature_valid?).to be true
    end
    
    it 'detects tampering' do
      event = create_audit_event
      
      # Simulate tampering (direct DB modification)
      AuditEvent.where(id: event.id).update_all(
        payload: { user_id: '999' }
      )
      
      tampered_event = E11y::AuditTrail.find(event.id)
      expect(tampered_event.signature_valid?).to be false
    end
  end
  
  describe 'retention policies' do
    it 'archives old events' do
      # Create event with 1 year retention
      Events::OldEvent.audit(
        data: 'test',
        retention_period: 1.year
      )
      
      # Simulate time passing
      travel 13.months
      
      # Run archival job
      E11y::AuditTrail::ArchivalJob.perform_now
      
      # Event should be archived (moved to cold storage)
      expect(AuditEvent.count).to eq(0)
      expect(ArchivedAuditEvent.count).to eq(1)
    end
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Define all configuration in event class**
```ruby
# ✅ GOOD: Configuration in class, NOT at call-time
module Events
  class UserDeleted < E11y::AuditEvent
    audit_retention 7.years
    audit_reason 'gdpr_article_17'
    
    schema do
      required(:user_id).filled(:string)
      required(:reason).filled(:string)
    end
  end
end

# Usage: Clean, no duplication!
Events::UserDeleted.audit(
  user_id: user.id,
  reason: 'gdpr_request'
  # ← No retention_period, audit_reason here!
)
```

**2. Audit all compliance-critical actions**
```ruby
# ✅ GOOD: Audit user deletion (GDPR)
Events::UserDeleted.audit(user_id: user.id, reason: 'gdpr_request')

# ✅ GOOD: Audit financial transactions (SOX)
Events::PaymentProcessed.audit(transaction_id: tx.id, amount: 99.99)

# ✅ GOOD: Audit data access (HIPAA)
Events::PatientDataAccessed.audit(patient_id: patient.id)
```

**3. Include justification/reason in schema**
```ruby
# ✅ GOOD: Require justification in schema
module Events
  class AdminUserModified < E11y::AuditEvent
    audit_retention 3.years
    
    schema do
      required(:user_id).filled(:string)
      required(:justification).filled(:string)  # ← REQUIRED!
    end
  end
end

# Must provide justification (schema validation!)
Events::AdminUserModified.audit(
  user_id: user.id,
  justification: 'User requested email change'
)
```

**4. Capture before/after state**
```ruby
# ✅ GOOD: Show what changed
before = user.attributes
user.update!(params)
Events::UserModified.audit(
  user_id: user.id,
  before_state: before,
  after_state: user.attributes,
  changes: user.previous_changes
)
```

---

### ❌ DON'T

**1. Don't put configuration at call-time**
```ruby
# ❌ BAD: Configuration scattered across codebase
Events::PaymentProcessed.audit(
  transaction_id: '123',
  retention_period: 7.years,    # ← WRONG! Should be in class
  audit_reason: 'sox_compliance' # ← WRONG! Should be in class
)

# ✅ GOOD: Configuration in event class
module Events
  class PaymentProcessed < E11y::AuditEvent
    audit_retention 7.years
    audit_reason 'sox_compliance'
  end
end
Events::PaymentProcessed.audit(transaction_id: '123')
```

**2. Don't use audit for non-compliance events**
```ruby
# ❌ BAD: Regular events don't need audit
Events::UserLoggedIn.audit(user_id: user.id)  # Overkill!

# ✅ GOOD: Use regular track
Events::UserLoggedIn.track(user_id: user.id)
```

**3. Don't store PII in audit without reason**
```ruby
# ❌ BAD: Unnecessary PII retention
module Events
  class UserAction < E11y::AuditEvent
    audit_retention 7.years  # ← Too long for PII?
    
    schema do
      required(:email).filled(:string)  # ← Do you NEED this?
    end
  end
end
```

**4. Don't allow audit event modification**
```ruby
# ❌ BAD: Never implement update/delete
def update_audit_event(id, new_data)
  # NO! Audit events are IMMUTABLE!
end
```

---

## 📚 Related Use Cases

- **[UC-007: PII Filtering](./UC-007-pii-filtering.md)** - Protect PII in audit logs
- **[UC-011: Rate Limiting](./UC-011-rate-limiting.md)** - Audit events bypass rate limits

---

## 🎯 Summary

### Compliance Requirements Met

| Standard | Requirement | E11y Support |
|----------|-------------|--------------|
| **GDPR** | Data deletion audit trail | ✅ 7-year retention |
| **HIPAA** | PHI access logging | ✅ 6-year retention |
| **SOX** | Financial transaction audit | ✅ 7-year retention |
| **PCI DSS** | Payment data access | ✅ 1-year retention |
| **ISO 27001** | Security event logs | ✅ Configurable |

### Key Features

- ✅ **Immutable** - Can't be modified after creation
- ✅ **Cryptographically signed** - Tamper detection
- ✅ **Separate storage** - Isolated from app DB
- ✅ **Long retention** - 1-10+ years
- ✅ **Searchable** - Query API for auditors
- ✅ **Compliance reports** - PDF/CSV generation
- ✅ **Access control** - Role-based audit access
- ✅ **Never dropped** - 100% guaranteed storage

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete
