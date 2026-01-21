# Contributing to E11y

Thank you for your interest in contributing to E11y! This document provides guidelines and instructions for contributing.

## 📋 Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Code Style](#code-style)
- [Submitting Changes](#submitting-changes)

## 🚀 Getting Started

### Prerequisites

- **Ruby 3.2+** (recommended: 3.3+)
- **Bundler 2.0+**
- **Docker & Docker Compose** (for integration tests)
- **Git**

### Fork and Clone

```bash
# Fork the repository on GitHub
# Then clone your fork
git clone git@github.com:YOUR_USERNAME/e11y.git
cd e11y
```

## 🔧 Development Setup

### 1. Install Dependencies

```bash
# Run setup script (configures bundle, installs dependencies)
bin/setup
```

This will:
- Configure bundle to exclude integration dependencies by default
- Install core dependencies
- Display available commands

### 2. Install Integration Dependencies (Optional)

For working on Rails integration, OpenTelemetry adapter, or other integrations:

```bash
bundle install --with integration
```

This installs:
- Rails 8.0
- OpenTelemetry SDK
- RSpec Rails
- Database Cleaner

## 🧪 Running Tests

E11y has two types of tests:

### Unit Tests (Default)

Fast, isolated tests without external dependencies:

```bash
bundle exec rspec
```

- **Duration**: ~2 minutes
- **Coverage**: 100% required
- **When to run**: Before every commit

### Integration Tests

Full tests with Rails, OpenTelemetry SDK, and docker-compose services:

```bash
# Option 1: Using helper script (recommended)
bin/test-integration

# Option 2: Manual
docker-compose up -d
INTEGRATION=true bundle exec rspec --tag integration
docker-compose down
```

- **Duration**: ~5 minutes
- **When to run**: Before submitting PR, when changing integrations
- **Requirements**: Docker, integration dependencies installed

See [Integration Testing Guide](testing/integration-tests.md) for detailed instructions.

### Running Specific Tests

```bash
# Run specific file
bundle exec rspec spec/e11y/event/base_spec.rb

# Run specific example
bundle exec rspec spec/e11y/event/base_spec.rb:42

# Run tests matching pattern
bundle exec rspec --tag validation
```

## 📝 Code Style

E11y follows the Ruby community style guide with RuboCop:

### Run Linter

```bash
# Check code style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a
```

### Key Conventions

- **100% test coverage** required
- **Type-safe code** - use dry-schema, dry-types
- **Thread-safe** - avoid shared mutable state
- **Performance-conscious** - zero-allocation patterns where possible
- **Documentation** - YARD comments for public APIs

## 🔒 Security

### Run Security Audits

```bash
# Check for vulnerable dependencies
bundle exec bundler-audit check --update

# Static security analysis
bundle exec brakeman
```

## 📦 Submitting Changes

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/issue-description
```

### 2. Make Your Changes

- Write tests first (TDD)
- Ensure all tests pass
- Update documentation
- Follow code style guidelines

### 3. Commit Your Changes

```bash
git add .
git commit -m "feat: add awesome feature

- Added X functionality
- Updated Y documentation
- Fixed Z edge case

Closes #123"
```

Use [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation only
- `refactor:` - Code refactoring
- `test:` - Adding tests
- `chore:` - Maintenance tasks

### 4. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a PR on GitHub with:
- Clear description of changes
- Link to related issue
- Screenshots (if UI changes)
- Test results

### 5. PR Review Process

Your PR will be reviewed for:
- ✅ All tests pass (unit + integration in CI)
- ✅ 100% code coverage maintained
- ✅ RuboCop passes
- ✅ Security audits pass
- ✅ Documentation updated
- ✅ Follows coding conventions

## 🐛 Reporting Bugs

### Before Reporting

1. Search existing issues
2. Check if bug still exists in main branch
3. Reproduce with minimal example

### Bug Report Template

```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce:
1. Configure E11y with...
2. Call `SomeEvent.track(...)`
3. See error

**Expected behavior**
What you expected to happen.

**Actual behavior**
What actually happened.

**Environment**
- Ruby version: 3.3.0
- E11y version: 1.0.0
- Rails version (if applicable): 8.0.0
- OS: macOS 14.0

**Additional context**
Any other relevant information.
```

## 💡 Suggesting Features

### Feature Request Template

```markdown
**Problem**
What problem does this solve?

**Proposed Solution**
How should E11y solve this?

**Alternatives**
What alternatives have you considered?

**Additional Context**
Examples, use cases, references.
```

## 📚 Development Resources

### Documentation

- [Architecture Decisions (ADRs)](../docs/)
- [Implementation Plan](IMPLEMENTATION_PLAN.md)
- [API Reference](API.md)
- [Integration Testing Guide](testing/integration-tests.md)

### Code Structure

```
lib/e11y/
├── event/           # Event system
├── adapters/        # Backend adapters
├── buffers/         # Memory buffers
├── middleware/      # Pipeline middleware
├── reliability/     # Retry, circuit breaker, DLQ
├── sampling/        # Sampling strategies
├── self_monitoring/ # Internal metrics
└── slo/            # SLO tracking
```

### Useful Commands

```bash
# Interactive console
bin/console

# Generate documentation
bundle exec yard doc

# Performance benchmarks
bundle exec ruby benchmarks/run_all.rb

# Check for breaking changes
bundle exec ruby scripts/check_compatibility.rb
```

## 🤝 Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](../CODE_OF_CONDUCT.md).

## 📧 Getting Help

- **Questions**: Open a GitHub Discussion
- **Bugs**: Open a GitHub Issue
- **Security**: Email security@e11y.dev (private disclosure)

## 🎉 Recognition

Contributors are recognized in:
- [CHANGELOG.md](../CHANGELOG.md)
- GitHub Contributors page
- Release notes

Thank you for contributing to E11y! 🚀
