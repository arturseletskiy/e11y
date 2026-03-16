# frozen_string_literal: true

require_relative "lib/e11y/version"

Gem::Specification.new do |spec|
  spec.name = "e11y"
  spec.version = E11y::VERSION
  spec.authors = ["Artur Seletskiy"]

  spec.summary = "E11y - Easy Telemetry: Observability for Rails developers who hate noise"
  spec.description = <<~DESC
    E11y (Easy Telemetry) - Observability for Rails developers who hate noise.

    UNIQUE FEATURES:
    • Request-scoped debug buffering - buffers debug logs in memory, flushes ONLY on errors
    • Zero-config SLO tracking - automatic Service Level Objectives for HTTP endpoints and jobs
    • Schema-validated events - catch bugs before production with dry-schema

    DEVELOPER EXPERIENCE:
    • Minimal setup — one config block, works with stdout out of the box
    • Auto-metrics from events (no manual Yabeda.increment)
    • Rails-first design (follows Rails conventions)
    • Pluggable adapters (Loki, Sentry, OpenTelemetry, custom backends)

    COST SAVINGS:
    • Reduce log storage costs by 90% (request-scoped buffering)
    • Replace expensive APM SaaS ($500-5k/month → infra costs only)
    • Own your observability data (no vendor lock-in)

    PRODUCTION-READY:
    • Thread-safe for multi-threaded Rails + Sidekiq
    • Adaptive sampling (error-based, load-based, value-based)
    • PII filtering (GDPR-compliant masking/hashing)
    • Performance optimized (hash-based events, minimal allocations)

    Perfect for Rails 7.0+ teams who need observability without complexity or high costs.
  DESC
  spec.homepage = "https://github.com/arturseletskiy/e11y"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/arturseletskiy/e11y"
  spec.metadata["changelog_uri"] = "https://github.com/arturseletskiy/e11y/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/arturseletskiy/blob/main/e11y/docs"
  spec.metadata["bug_tracker_uri"] = "https://github.com/arturseletskiy/e11y/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile docs/researches/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "concurrent-ruby", "~> 1.2" # Thread-safe data structures
  spec.add_dependency "dry-schema", "~> 1.13" # Event schema validation
  spec.add_dependency "dry-types", "~> 1.7"
  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "zeitwerk", "~> 2.6"

  # Development dependencies
  spec.add_development_dependency "benchmark-ips", "~> 2.13" # For performance benchmarks
  spec.add_development_dependency "memory_profiler", "~> 1.0" # For memory profiling
  spec.add_development_dependency "rack", ">= 2.2.4" # For Rack middleware testing (supports Rails 7.0+)
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 3.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "webmock", "~> 3.19" # For HTTP adapter testing
  spec.add_development_dependency "yard", "~> 0.9"

  # Optional adapter dependencies (install only if using specific adapters)
  # LokiAdapter: gem install faraday faraday-retry
  # SentryAdapter: gem install sentry-ruby
  spec.add_development_dependency "faraday", "~> 2.7" # For LokiAdapter
  spec.add_development_dependency "faraday-retry", "~> 2.2" # For LokiAdapter retry middleware
  spec.add_development_dependency "sentry-ruby", "~> 5.15" # For SentryAdapter
end
