# E11y Guides

This directory contains user-facing guides for using E11y in production.

## Planned Guides (Phase 5):

1. **Getting Started**
   - Installation
   - Basic configuration
   - First event tracking

2. **Configuration**
   - DSL reference
   - Adapter setup (Loki, Sentry, OpenTelemetry)
   - Middleware configuration

3. **Event Definition**
   - Schema definition with dry-schema
   - PII filtering
   - Event-level adapter configuration

4. **Rails Integration**
   - Railtie auto-setup
   - ActiveSupport::Notifications bridge
   - Sidekiq/ActiveJob middleware

5. **Production Deployment**
   - Performance tuning
   - Memory optimization
   - Monitoring & SLO tracking
   - Security & compliance (GDPR, SOC2)

6. **Troubleshooting**
   - Common issues
   - Debug mode
   - Performance profiling

## Current Status

All guides will be written during Phase 5 (Production Readiness).
For now, see:
- `docs/QUICK-START.md` - Quick start guide
- `docs/ADR-*.md` - Architecture decisions
- `docs/use_cases/UC-*.md` - Use cases
