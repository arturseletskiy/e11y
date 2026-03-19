# Contributing to e11y

Thank you for your interest in contributing to e11y! This document provides guidelines and best practices for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Commit Message Guidelines](#commit-message-guidelines)
- [Pull Request Process](#pull-request-process)
- [Testing Guidelines](#testing-guidelines)
- [Code Style](#code-style)

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

---

## Getting Started

### Prerequisites

- Ruby 3.2 or 3.3
- Bundler 2.x
- Git

### Setup

```bash
# Clone the repository (fork first on GitHub)
git clone https://github.com/YOUR_USERNAME/e11y.git
cd e11y

# Run setup script (configures bundle, installs dependencies)
bin/setup

# Run tests
bundle exec rake spec:unit
bundle exec rake spec:integration
bundle exec rake spec:railtie

# Check code style
bundle exec rubocop
```

### Integration Dependencies (Optional)

For integration tests, Rails adapter, or OpenTelemetry:

```bash
bundle install --with integration
```

For Loki/OTel integration tests, start services first:

```bash
docker compose up -d loki otel-collector
INTEGRATION=true bundle exec rspec spec/integration/
```

---

## Development Workflow

### 1. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

**Branch Naming Convention:**
- `feature/` - New features
- `fix/` - Bug fixes
- `refactor/` - Code refactoring
- `test/` - Test improvements
- `docs/` - Documentation updates
- `chore/` - Maintenance tasks

### 2. Make Your Changes

- Write tests first (TDD approach)
- Ensure all tests pass
- Follow Ruby style guide (enforced by RuboCop)
- Add documentation for new features
- Update CHANGELOG.md

### 3. Commit Your Changes

Follow [Conventional Commits](#commit-message-guidelines) format:

```bash
git add .
git commit -m "feat(adapters): add OpenTelemetry logs adapter"
```

### 4. Push and Create PR

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

---

## Commit Message Guidelines

We use [Conventional Commits](https://www.conventionalcommits.org/) for clear and structured commit messages.

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type

- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation only
- `style` - Formatting (no code change)
- `refactor` - Code refactoring
- `perf` - Performance improvements
- `test` - Adding/updating tests
- `chore` - Maintenance tasks
- `ci` - CI/CD changes

### Scope

Component affected (optional but recommended):

- `adapters` - Adapters (Loki, Sentry, etc)
- `buffers` - Buffer implementations
- `events` - Event classes
- `instruments` - ActiveJob, Sidekiq, Rails
- `middleware` - Middleware stack
- `metrics` - Metrics and cardinality
- `pipeline` - Event pipeline
- `reliability` - Circuit breaker, DLQ, retry
- `sampling` - Sampling strategies
- `slo` - SLO tracking
- `rails` - Rails integration
- `ci` - CI/CD
- `deps` - Dependencies
- `docs` - Documentation
- `test` - Test infrastructure
- `config` - Configuration

### Subject

- Use imperative mood: "add" not "added"
- Don't capitalize first letter
- No period at the end
- Maximum 72 characters

### Examples

**Good Commit Messages:**

```
feat(adapters): add OpenTelemetry logs adapter

Implement OTelLogs adapter with:
- Severity mapping (Ruby Logger → OpenTelemetry)
- Attribute conversion (tags → log attributes)
- Trace context propagation

Closes #42

---

fix(buffers): prevent memory leak in ring buffer

Ring buffer was not releasing old events when capacity reached.
Added proper cleanup in #push method.

Performance impact: minimal (< 1% overhead)

---

refactor(middleware): extract routing logic to separate class

Routing logic was embedded in Middleware::Base making it hard to test.
Extracted to Middleware::Routing for better separation of concerns.

---

test(integration): add Rails 8.0 compatibility tests

Added test matrix for Ruby 3.2/3.3 × Rails 7.0/7.1/8.0
All combinations pass except Rails 8.0 exception handling (known issue)

---

docs(readme): update installation instructions

Added section on Rails 8.0 compatibility
Updated gem version requirement to ~> 0.1.1
```

**Bad Commit Messages:**

```
Fix                          # Too vague, no scope, no description
Update                       # Not descriptive
WIP                          # Work in progress should not be committed
Changes                      # Too generic
fix: Fix bug                 # Redundant, should be: fix(scope): describe the bug
Fixed the thing              # Not imperative mood, no scope
feat: added new feature.     # Should be lowercase, no period
```

### Commit Message Linting

We use commitlint to enforce these rules:

```bash
# Install commitlint (one-time setup)
npm install -g @commitlint/cli @commitlint/config-conventional

# Check last commit
commitlint --from HEAD~1 --to HEAD --verbose

# Check all commits in branch
commitlint --from main --to HEAD --verbose
```

---

## Pull Request Process

### Before Creating PR

1. **Ensure your branch is up to date:**
   ```bash
   git checkout main
   git pull origin main
   git checkout your-branch
   git rebase main
   ```

2. **Run all tests:**
   ```bash
   bundle exec rake spec:unit
   bundle exec rake spec:integration
   bundle exec rake spec:railtie
   ```

3. **Check code style:**
   ```bash
   bundle exec rubocop
   ```

4. **Verify coverage:**
   ```bash
   bundle exec rake spec:coverage
   # Coverage should be ≥95%
   ```

5. **Update documentation:**
   - Update README.md if needed
   - Add/update CHANGELOG.md
   - Create ADR if making architectural decision

### PR Guidelines

- **Keep PRs small:** \<500 lines of code
- **One logical change per PR:** Don't mix refactoring with features
- **Write descriptive PR title:** Follow Conventional Commits format
- **Fill out PR template:** Don't skip sections
- **Self-review:** Read your own PR before requesting review
- **Add tests:** PRs without tests will not be merged
- **Update docs:** Update relevant documentation

### PR Title Format

Same as commit messages:

```
feat(adapters): add OpenTelemetry logs adapter
fix(buffers): prevent memory leak in ring buffer
docs(readme): update installation instructions
```

### PR Size Guidelines

| Lines Changed | Review Time | Merge Probability |
|---------------|-------------|-------------------|
| \<100 | 30 min | 95% |
| 100-300 | 1-2 hours | 85% |
| 300-500 | 2-4 hours | 70% |
| \>500 | 4+ hours | 50% |

**Recommendation:** Break large PRs into smaller, logical units.

### Stacked PRs

For large features, use stacked PRs:

```
PR #1: feat(adapters): add OTel base adapter
  └── PR #2: feat(adapters): add OTel logs adapter
      └── PR #3: feat(adapters): add OTel metrics adapter
```

Each PR builds on the previous one and can be reviewed independently.

---

## Testing Guidelines

### Test Organization

```
spec/
├── e11y/               # Unit tests (fast, isolated)
├── integration/        # Integration tests (Rails app, adapters)
└── support/            # Shared test helpers
```

### Test Types

**Unit Tests** (`spec/e11y/`):
- Fast (\<10ms each)
- No external dependencies
- Test single class/module
- Use mocks/stubs liberally

**Integration Tests** (`spec/integration/`):
- Slower (50-500ms each)
- Full Rails app
- Test component interactions
- Minimal mocking

### Running Tests

```bash
# All tests
bundle exec rspec

# Unit tests only
bundle exec rake spec:unit

# Integration tests only
bundle exec rake spec:integration

# Specific file
bundle exec rspec spec/e11y/buffers/ring_buffer_spec.rb

# Specific example
bundle exec rspec spec/e11y/buffers/ring_buffer_spec.rb:42
```

### Test Coverage

We maintain ≥95% test coverage:

```bash
# Generate coverage report
bundle exec rake spec:coverage

# View report
open coverage/index.html
```

**Coverage Requirements:**
- New code: 100% coverage
- Modified code: Maintain or improve coverage
- Exceptions: Document in PR why coverage is lower

### Writing Good Tests

```ruby
# Good test structure
RSpec.describe E11y::Buffers::RingBuffer do
  subject(:buffer) { described_class.new(capacity: 3) }

  describe '#push' do
    context 'when buffer is not full' do
      it 'adds event to buffer' do
        buffer.push(event)
        expect(buffer.size).to eq(1)
      end
    end

    context 'when buffer is full' do
      before do
        3.times { buffer.push(create_event) }
      end

      it 'evicts oldest event' do
        oldest_event = buffer.first
        buffer.push(new_event)
        expect(buffer).not_to include(oldest_event)
      end
    end
  end
end
```

**Test Best Practices:**
- One assertion per test (when possible)
- Use descriptive test names
- Use `let` for shared setup
- Use `subject` for the object under test
- Use `before` for common setup
- Use `context` for different scenarios
- Test edge cases and error paths

---

## Code Style

### Ruby Style Guide

We follow the [Ruby Style Guide](https://rubystyle.guide/) enforced by RuboCop.

### Key Conventions

**Naming:**
```ruby
# Classes: PascalCase
class EventProcessor
end

# Methods: snake_case
def process_event(event)
end

# Constants: SCREAMING_SNAKE_CASE
MAX_BUFFER_SIZE = 1000

# Files: snake_case.rb
lib/e11y/buffers/ring_buffer.rb
```

**Code Organization:**
```ruby
# Order: constants, attributes, initializer, public, protected, private
class Adapter
  MAX_RETRIES = 3

  attr_reader :config

  def initialize(config)
    @config = config
  end

  def emit(event)
    # public method
  end

  protected

  def validate(event)
    # protected method
  end

  private

  def internal_method
    # private method
  end
end
```

**Performance:**
```ruby
# Use #each instead of #map when not using return value
events.each { |event| process(event) }

# Use #select instead of #map + #compact
events.select { |event| event.valid? }

# Use ||= for memoization
def expensive_calculation
  @result ||= perform_calculation
end
```

### RuboCop

```bash
# Check violations
bundle exec rubocop

# Auto-fix (safe corrections only)
bundle exec rubocop --auto-correct

# Auto-fix (including unsafe corrections)
bundle exec rubocop --auto-correct-all

# Check specific file
bundle exec rubocop lib/e11y/buffers/ring_buffer.rb
```

### RuboCop Configuration

Our RuboCop config (`.rubocop.yml`) enforces:
- Ruby 3.2+ syntax
- Max line length: 120 characters
- Max method length: 25 lines
- Max class length: 250 lines
- Max cyclomatic complexity: 10

---

## Documentation

### Project Documentation

- [Architecture Decisions (ADRs)](docs/ADR-INDEX.md)
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)
- [Quick Start](docs/QUICK-START.md)

### Code Documentation

Use YARD for documentation:

```ruby
# @param event [E11y::Event::Base] Event to emit
# @param options [Hash] Additional options
# @option options [Boolean] :async (false) Emit asynchronously
# @return [Boolean] true if successful
# @raise [ArgumentError] if event is invalid
#
# @example Emit event synchronously
#   adapter.emit(event)
#
# @example Emit event asynchronously
#   adapter.emit(event, async: true)
def emit(event, options = {})
  # implementation
end
```

### Inline Comments

```ruby
# Good: Explain WHY, not WHAT
# Buffer uses ring structure to prevent unbounded growth
# while maintaining insertion performance O(1)
buffer = RingBuffer.new(capacity: 1000)

# Bad: Obvious comment (don't do this)
# Create new buffer
buffer = RingBuffer.new
```

---

## Architecture Decision Records (ADRs)

For significant architectural decisions, create an ADR in `docs/`:

```bash
# Create new ADR (see docs/ADR-INDEX.md for numbering)
# Follow format of existing ADRs (ADR-001-architecture.md, etc.)
```

**When to create ADR:**
- Changing core architecture
- Adding/removing major dependencies
- Breaking API changes
- Performance vs maintainability tradeoffs

**ADR Template:**
```markdown
# ADR-018: Title

## Status
Proposed | Accepted | Deprecated | Superseded by ADR-XXX

## Context
What is the problem we're solving?

## Decision
What did we decide to do?

## Consequences
What are the positive and negative outcomes?

## Alternatives Considered
What other options did we consider?
```

---

## Security

```bash
# Check for vulnerable dependencies
bundle exec bundler-audit check --update

# Static security analysis (if Brakeman installed)
bundle exec brakeman
```

## Reporting Bugs

**Before reporting:** Search existing issues, verify bug exists in main.

**Bug report template:**
- Describe the bug
- Steps to reproduce
- Expected vs actual behavior
- Environment (Ruby, E11y, Rails, OS versions)

## Suggesting Features

**Feature request template:**
- Problem being solved
- Proposed solution
- Alternatives considered
- Additional context

## Getting Help

- **Questions:** Open a GitHub Discussion
- **Bugs:** Open a GitHub Issue
- **Security:** Private disclosure via GitHub Security Advisories

---

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to e11y! 🎉
