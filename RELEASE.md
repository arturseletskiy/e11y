# Release Instructions for e11y

## Quick Release (Automated)

```bash
# 1. Bump version (updates VERSION + CHANGELOG)
rake release:bump
# Enter new version when prompted, e.g., 0.2.0

# 2. Review and commit
git diff
git add -A
git commit -m "Bump version to 0.2.0"

# 3. Full release (test + build + tag + push + publish)
rake release:full
```

For more control, see [Step-by-Step Release](#step-by-step-release) below.

## Pre-Release Checklist

### Core
- [ ] All changes documented in CHANGELOG.md under `[Unreleased]`
- [ ] Version bumped: `rake release:bump`
- [ ] All tests passing: `rake spec:all` (unit + integration)
- [ ] RuboCop clean: `bundle exec rubocop`
- [ ] Changes committed
- [ ] Git tag created
- [ ] Published to RubyGems.org
- [ ] GitHub release created

### Documentation & Links
- [ ] All doc links valid (ADRs in `docs/architecture/`, use cases in `docs/use_cases/`)
- [ ] No broken references to deleted files (e.g. `docs/analysis/`, `docs/IMPLEMENTATION_PLAN.md`)
- [ ] README, CONTRIBUTING, CLAUDE.md reference correct paths
- [ ] All user-facing text in English (no Russian in docs/code comments)

### Production Readiness
- [ ] SECURITY.md present (if handling sensitive data)
- [ ] LICENSE file present and correct
- [ ] No TODO/FIXME in critical paths
- [ ] Deprecation warnings documented (if any)
- [ ] Breaking changes clearly called out in CHANGELOG

## Step-by-Step Release

### Step 0: Bump Version

First, update version and CHANGELOG:

```bash
rake release:bump
```

This will:
1. Prompt for new version (e.g., 0.2.0)
2. Update `lib/e11y/version.rb`
3. Convert `[Unreleased]` → `[0.2.0] - YYYY-MM-DD` in CHANGELOG
4. Add new empty `[Unreleased]` section

Commit the changes:

```bash
git add -A
git commit -m "Bump version to 0.2.0"
```

### Step 1: Prepare Release

Run tests, build both gems, create tag:

```bash
rake release:prep
```

This will:
- ✅ Check git status (fails if uncommitted changes)
- ✅ Run full test suite
- ✅ Build **e11y** and **e11y-devtools** `.gem` files (devtools is built under `gems/e11y-devtools/`)
- ✅ Create annotated git tag `v<e11y-version>` (tag follows the core gem only)

Build gems without tests (e.g. after a failed spec run you already trust):

```bash
rake release:build_gems
```

Or manually:

```bash
# Run all tests
bundle exec rspec

# Build gems
gem build e11y.gemspec
(cd gems/e11y-devtools && gem build e11y-devtools.gemspec)

# Create and push tag
git tag -a v0.2.0 -m "Release v0.2.0"
git push origin main
git push origin v0.2.0
```

### Step 2: Push to GitHub

```bash
rake release:git_push
```

This will:
- ✅ Verify tag exists
- ✅ Push commits to origin/main
- ✅ Push tag to origin
- ✅ Show GitHub release URL

### Step 3: Publish to RubyGems.org

```bash
rake release:gem_push
```

This will:
- ✅ Verify both `.gem` files exist (e11y in repo root, e11y-devtools under `gems/e11y-devtools/`)
- ✅ Prompt once for confirmation
- ✅ Push **e11y** first, then **e11y-devtools** (each `gem push` may ask for MFA)

Push only one gem if needed:

```bash
rake release:rubygems:push_core      # e11y only
rake release:rubygems:push_devtools  # e11y-devtools only
```

Or manually:

### Prerequisites

1. **RubyGems Account**: Create account at https://rubygems.org/sign_up
2. **API Key**: Get your API key from https://rubygems.org/profile/edit
3. **MFA Enabled**: This gem requires MFA (configured in gemspec)

### Publish Command

```bash
# Sign in to RubyGems (one-time setup)
gem signin

# Push the gems (requires MFA; e11y first — devtools depends on it)
gem push e11y-0.1.0.gem
gem push gems/e11y-devtools/e11y-devtools-0.1.0.gem
```

Expected output:
```
Pushing gem to https://rubygems.org...
Enter your RubyGems.org credentials.
Username: [your_username]
Password: [your_password]
MFA Code: [6-digit code from authenticator app]
Successfully registered gem: e11y (0.1.0)
```

### Verify Publication

```bash
# Check gem is available
gem search e11y --remote

# Install from RubyGems
gem install e11y
```

## Step 3: Create GitHub Release

1. Go to https://github.com/arturseletskiy/e11y/releases/new
2. Choose tag: `v0.1.0`
3. Release title: `v0.1.0 - First Production Release`
4. Description: Use content from CHANGELOG.md (see below)
5. Attach binary: Upload `e11y-0.1.0.gem`
6. Click "Publish release"

### GitHub Release Notes Template

```markdown
# 🎉 E11y 0.1.0 - First Production Release

Production-ready observability gem for Ruby on Rails with zero-config SLO tracking, request-scoped buffering, and high-performance event streaming.

## 🚀 Highlights

- **Zero-Config SLO Tracking** - Automatic Service Level Objectives for HTTP and background jobs
- **100K+ events/sec** - Benchmark-validated performance (p99 <50μs latency)
- **99%+ Test Coverage** - 1409 test examples, battle-tested
- **16 ADRs** - Fully documented architecture decisions
- **Cardinality Protection** - 4-layer defense against metric explosions
- **Production-Ready** - Reliability layer with retry, circuit breaker, DLQ

## 📦 Installation

```ruby
# Gemfile
gem 'e11y', '~> 1.0'
```

```bash
bundle install
```

## 📚 Documentation

- **Quick Start**: [README.md](https://github.com/arturseletskiy/e11y#quick-start)
- **Architecture**: [docs/architecture/ADR-INDEX.md](https://github.com/arturseletskiy/e11y/blob/main/docs/architecture/ADR-INDEX.md)
- **Benchmarks**: [benchmarks/README.md](https://github.com/arturseletskiy/e11y/blob/main/benchmarks/README.md)

## 🔥 What's New

See [CHANGELOG.md](https://github.com/arturseletskiy/e11y/blob/main/CHANGELOG.md) for full details.

### Core Features (Phase 1-2)
- Event System with dry-schema validation
- Pipeline Architecture (middleware-based)
- 7 Adapters: Stdout, File, InMemory, Loki, Sentry, OpenTelemetry, Yabeda
- 3 Buffer Types: RingBuffer, EphemeralBuffer, AdaptiveBuffer
- Reliability: Retry, Circuit Breaker, Dead Letter Queue

### SLO Tracking (Phase 3)
- Event-Driven SLOs for HTTP/jobs
- Stratified Sampling (latency-aware)
- Error Spike Detection
- Value-Based Sampling

### Rails Integration (Phase 4)
- Auto-instrumentation for Rails events
- HTTP request tracking
- Background job tracking (ActiveJob, Sidekiq)
- Database query events
- Logger bridge (Rails.logger → E11y)

### Scale & Performance (Phase 5)
- Cardinality Protection (4-layer defense)
- Tiered Storage (hot/warm/cold)
- Benchmarked: 100K events/sec, p99 <50μs

## ⚡ Performance

| Scale | Latency (p99) | Throughput | Memory |
|-------|--------------|------------|---------|
| Small (1K/s) | 47μs | 107K/s | 1.95 MB |
| Medium (10K/s) | 33μs | 110K/s | 19.49 MB |
| Large (100K/s) | 26μs | 109K/s | 194.93 MB |

## 🙏 Credits

Built with patterns from Devise, Sidekiq, Puma, Dry-rb, Yabeda, and Sentry.

---

**Full Changelog**: https://github.com/arturseletskiy/e11y/blob/main/CHANGELOG.md
```

## Post-Release Tasks

- [ ] Announce on Twitter/social media
- [ ] Update README badge with latest version
- [ ] Monitor RubyGems download stats
- [ ] Monitor GitHub issues for bug reports

## Rollback Procedure (if needed)

If critical bug found after release:

```bash
# Yank the gem (makes it unavailable for new installs)
gem yank e11y -v 0.1.0

# Fix the issue, bump to 1.0.1, and re-release
```

## Support

- **Issues**: https://github.com/arturseletskiy/e11y/issues
- **Discussions**: https://github.com/arturseletskiy/e11y/discussions
