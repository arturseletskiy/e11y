# frozen_string_literal: true

#
# E11y Gem Rakefile
#
# Quick reference:
#   rake                   # Run tests and rubocop
#   rake release:bump      # Bump version and update CHANGELOG (interactive)
#   rake release:full      # Complete release workflow (prep + git_push + gem_push)
#   rake release:prep      # Run tests, build gem, create tag
#   rake release:git_push  # Push to GitHub
#   rake release:gem_push  # Publish to RubyGems
#   rake spec:all          # Run all test suites
#   rake spec:unit         # Run unit tests only (fast)
#   rake spec:integration  # Run integration tests
#
# See RELEASE.md for detailed release instructions

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# Test suite tasks
namespace :spec do
  desc "Run unit tests only (fast, no Rails/integrations)"
  task :unit do
    sh "bundle exec rspec spec/e11y spec/e11y_spec.rb spec/zeitwerk_spec.rb"
  end

  desc "Run integration tests (requires Rails, bundle install --with integration)"
  task :integration do
    # Run integration tests with explicit file patterns to avoid loading all specs
    # This prevents test pollution from unit test files
    sh "INTEGRATION=true bundle exec rspec " \
       "spec/integration/*.rb " \
       "spec/e11y/adapters/*_spec.rb " \
       "spec/e11y/instruments/*_spec.rb " \
       "--tag integration"
  end

  desc "Run railtie integration tests (separate Rails app instance)"
  task :railtie do
    sh "bundle exec rspec spec/e11y/railtie_integration_spec.rb --tag railtie_integration"
  end

  desc "Run all tests (unit + integration + railtie, ~1729 examples)"
  task :all do
    puts "\n#{'=' * 80}"
    puts "Running UNIT tests (spec/e11y + top-level specs)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:unit"].invoke

    puts "\n#{'=' * 80}"
    puts "Running INTEGRATION tests (spec/integration)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:integration"].invoke

    puts "\n#{'=' * 80}"
    puts "Running RAILTIE tests (Rails initialization)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:railtie"].invoke

    puts "\n#{'=' * 80}"
    puts "✅ All test suites completed!"
    puts "#{'=' * 80}\n"
  end

  desc "Run tests with coverage report"
  task :coverage do
    sh "COVERAGE=true bundle exec rspec"
  end

  desc "Run integration tests with coverage"
  task :coverage_integration do
    sh "COVERAGE=true INTEGRATION=true bundle exec rspec spec/integration/"
  end

  desc "Run benchmark tests (performance tests, slow)"
  task :benchmark do
    sh "bundle exec rspec spec/e11y --tag benchmark"
  end

  desc "Run ALL tests including benchmarks (very slow)"
  task :everything do
    puts "\n#{'=' * 80}"
    puts "Running ALL tests (unit + integration + railtie + benchmarks)"
    puts "#{'=' * 80}\n"
    Rake::Task["spec:unit"].invoke
    Rake::Task["spec:integration"].invoke
    Rake::Task["spec:railtie"].invoke
    Rake::Task["spec:benchmark"].invoke

    puts "\n#{'=' * 80}"
    puts "✅ All test suites including benchmarks completed!"
    puts "#{'=' * 80}\n"
  end
end

# Custom tasks
namespace :e11y do
  desc "Start interactive console"
  task :console do
    require "pry"
    require_relative "lib/e11y"
    Pry.start
  end

  desc "Run performance benchmarks"
  task :benchmark do
    ruby "spec/benchmarks/run_all.rb"
  end

  desc "Generate documentation"
  task :docs do
    sh "yard doc"
  end

  desc "Run security audit"
  task :audit do
    sh "bundle exec bundler-audit check --update"
    sh "bundle exec brakeman --no-pager"
  end
end

# Custom release automation (extends bundler/gem_tasks)
# Note: bundler/gem_tasks provides: release, release:guard_clean, release:rubygem_push, etc.
# Our tasks provide more control and visibility
namespace :release do
  desc "Bump version and update CHANGELOG (interactive)"
  task :bump do
    require_relative "lib/e11y/version"
    current_version = E11y::VERSION

    puts "\n#{'=' * 80}"
    puts "📝 Version Bump"
    puts "#{'=' * 80}\n"
    puts "Current version: #{current_version}"
    puts "\nEnter new version (e.g., 0.2.0, 1.0.0):"

    new_version = $stdin.gets.chomp.strip

    if new_version.empty?
      puts "❌ Error: Version cannot be empty"
      exit 1
    end

    unless new_version.match?(/^\d+\.\d+\.\d+$/)
      puts "❌ Error: Invalid version format. Use semantic versioning (e.g., 0.2.0)"
      exit 1
    end

    if new_version == current_version
      puts "⚠️  Warning: New version is the same as current version"
      puts "Continue anyway? (y/N)"
      response = $stdin.gets.chomp.downcase
      exit 0 unless %w[y yes].include?(response)
    end

    puts "\n[1/3] Updating lib/e11y/version.rb..."
    version_file = "lib/e11y/version.rb"
    version_content = File.read(version_file)
    updated_version_content = version_content.gsub(
      /VERSION = "#{Regexp.escape(current_version)}"/,
      "VERSION = \"#{new_version}\""
    )
    File.write(version_file, updated_version_content)
    puts "✅ Updated: #{current_version} → #{new_version}"

    puts "\n[2/3] Updating CHANGELOG.md..."
    changelog_file = "CHANGELOG.md"
    changelog_content = File.read(changelog_file)

    # Check if there's an [Unreleased] section
    today = Time.now.strftime("%Y-%m-%d")
    if changelog_content.include?("## [Unreleased]")
      # Replace [Unreleased] with version and date
      updated_changelog = changelog_content.sub(
        "## [Unreleased]",
        "## [#{new_version}] - #{today}"
      )

      # Add new [Unreleased] section at the top
      updated_changelog = updated_changelog.sub(
        /(## \[#{Regexp.escape(new_version)}\] - #{today})/,
        "## [Unreleased]\n\n### Added\n\n### Changed\n\n### Fixed\n\n### Deprecated\n\n### Removed\n\n### Security\n\n\\1"
      )

      File.write(changelog_file, updated_changelog)
      puts "✅ Updated CHANGELOG.md:"
      puts "   - [Unreleased] → [#{new_version}] - #{today}"
      puts "   - Added new [Unreleased] section"
    else
      # No [Unreleased] section, just add version entry

      # Find where to insert (after the header, before first version)
      if /(## \[\d+\.\d+\.\d+\])/.match?(changelog_content)
        updated_changelog = changelog_content.sub(
          /(## \[\d+\.\d+\.\d+\])/,
          "## [Unreleased]\n\n### Added\n\n### Changed\n\n### Fixed\n\n### Deprecated\n\n### Removed\n\n### Security\n\n## [#{new_version}] - #{today}\n\n### Added\n- Version bump\n\n\\1"
        )
      else
        # No previous versions, add after header
        header_end = changelog_content.index("\n\n") || 0
        header = changelog_content[0..header_end]
        rest = changelog_content[(header_end + 1)..] || ""
        updated_changelog = "#{header}\n## [#{new_version}] - #{today}\n\n### Added\n- Initial release\n\n#{rest}"
      end

      File.write(changelog_file, updated_changelog)
      puts "✅ Added version [#{new_version}] - #{today} to CHANGELOG.md"
    end

    puts "\n[3/3] Summary"
    puts "✅ Version bumped: #{current_version} → #{new_version}"
    puts "✅ Files updated:"
    puts "   - lib/e11y/version.rb"
    puts "   - CHANGELOG.md"

    puts "\n#{'=' * 80}"
    puts "Next steps:"
    puts "  1. Review changes: git diff"
    puts "  2. Commit changes: git add -A && git commit -m 'Bump version to #{new_version}'"
    puts "  3. Release: rake release:prep"
    puts "#{'=' * 80}\n"
  end

  desc "Prepare release: run tests, build gem, create git tag (safe)"
  task :prep do
    require_relative "lib/e11y/version"
    version = E11y::VERSION

    puts "\n#{'=' * 80}"
    puts "📦 Preparing release for e11y v#{version}"
    puts "#{'=' * 80}\n"

    # Step 1: Check git status
    puts "\n[1/5] Checking git status..."
    unless system("git diff-index --quiet HEAD --")
      puts "❌ Error: You have uncommitted changes. Please commit them first."
      exit 1
    end
    puts "✅ Git working directory is clean"

    # Step 2: Run tests
    puts "\n[2/5] Running tests..."
    unless system("bundle exec rspec")
      puts "❌ Error: Tests failed. Please fix them before releasing."
      exit 1
    end
    puts "✅ All tests passed"

    # Step 3: Build gem
    puts "\n[3/5] Building gem..."
    unless system("gem build e11y.gemspec")
      puts "❌ Error: Failed to build gem"
      exit 1
    end
    puts "✅ Gem built: e11y-#{version}.gem"

    # Step 4: Create git tag
    puts "\n[4/5] Creating git tag..."
    tag_name = "v#{version}"
    tag_message = "Release v#{version}"

    if system("git rev-parse #{tag_name} >/dev/null 2>&1")
      puts "⚠️  Warning: Tag #{tag_name} already exists"
    else
      unless system("git tag -a #{tag_name} -m '#{tag_message}'")
        puts "❌ Error: Failed to create git tag"
        exit 1
      end
      puts "✅ Git tag created: #{tag_name}"
    end

    # Step 5: Summary
    puts "\n[5/5] Release preparation complete!"
    puts "\n#{'=' * 80}"
    puts "📦 Release v#{version} is ready!"
    puts "#{'=' * 80}\n"
    puts "Next steps:"
    puts "  1. Review CHANGELOG.md"
    puts "  2. Push to GitHub:"
    puts "     git push origin main"
    puts "     git push origin #{tag_name}"
    puts "  3. Publish to RubyGems:"
    puts "     rake release:publish"
    puts "\n"
  end

  desc "Publish gem to RubyGems.org (requires authentication, safe)"
  task :gem_push do
    require_relative "lib/e11y/version"
    version = E11y::VERSION
    gem_file = "e11y-#{version}.gem"

    puts "\n#{'=' * 80}"
    puts "📤 Publishing e11y v#{version} to RubyGems.org"
    puts "#{'=' * 80}\n"

    unless File.exist?(gem_file)
      puts "❌ Error: Gem file not found: #{gem_file}"
      puts "Run 'rake release:prep' first"
      exit 1
    end

    puts "This will publish #{gem_file} to RubyGems.org"
    puts "You will be prompted for your RubyGems credentials and MFA code."
    puts "\nContinue? (y/N)"

    response = $stdin.gets.chomp.downcase
    unless %w[y yes].include?(response)
      puts "❌ Publication cancelled"
      exit 0
    end

    unless system("gem push #{gem_file}")
      puts "\n❌ Error: Failed to publish gem"
      puts "Make sure you have:"
      puts "  1. RubyGems account (https://rubygems.org/sign_up)"
      puts "  2. Signed in: gem signin"
      puts "  3. MFA enabled on your account"
      exit 1
    end

    puts "\n✅ Successfully published e11y v#{version} to RubyGems.org!"
    puts "\nVerify: https://rubygems.org/gems/e11y/versions/#{version}"
  end

  desc "Push git changes and tag to GitHub (safe)"
  task :git_push do
    require_relative "lib/e11y/version"
    version = E11y::VERSION
    tag_name = "v#{version}"

    puts "\n#{'=' * 80}"
    puts "🚀 Pushing to GitHub"
    puts "#{'=' * 80}\n"

    unless system("git rev-parse #{tag_name} >/dev/null 2>&1")
      puts "❌ Error: Tag #{tag_name} does not exist"
      puts "Run 'rake release:prep' first"
      exit 1
    end

    puts "[1/2] Pushing commits to origin/main..."
    unless system("git push origin main")
      puts "❌ Error: Failed to push commits"
      exit 1
    end
    puts "✅ Commits pushed"

    puts "\n[2/2] Pushing tag #{tag_name}..."
    unless system("git push origin #{tag_name}")
      puts "❌ Error: Failed to push tag"
      exit 1
    end
    puts "✅ Tag pushed"

    puts "\n✅ Successfully pushed to GitHub!"
    puts "\nCreate GitHub release: https://github.com/arturseletskiy/e11y/releases/new?tag=#{tag_name}"
  end

  desc "Complete release workflow: prep, git_push, and gem_push (interactive)"
  task :full do
    Rake::Task["release:prep"].invoke

    puts "\n#{'=' * 80}"
    puts "Ready to push to GitHub and publish to RubyGems?"
    puts "=" * 80
    puts "This will:"
    puts "  1. Push commits and tag to GitHub"
    puts "  2. Publish gem to RubyGems.org"
    puts "\nContinue? (y/N)"

    response = $stdin.gets.chomp.downcase
    unless %w[y yes].include?(response)
      puts "\n⏸️  Release prepared but not published"
      puts "To continue later, run:"
      puts "  rake release:git_push  # Push to GitHub"
      puts "  rake release:gem_push  # Publish to RubyGems"
      exit 0
    end

    Rake::Task["release:git_push"].invoke
    Rake::Task["release:gem_push"].invoke

    puts "\n#{'=' * 80}"
    puts "🎉 Release complete!"
    puts "=" * 80
    puts "\nPost-release tasks:"
    puts "  1. Create GitHub release: https://github.com/arturseletskiy/e11y/releases/new"
    puts "  2. Verify on RubyGems: https://rubygems.org/gems/e11y"
    puts "  3. Update README badges"
    puts "  4. Announce on social media"
    puts "\n"
  end

  desc "Clean up built gems"
  task :clean do
    puts "🧹 Cleaning up gem files..."
    FileList["*.gem"].each do |gem_file|
      File.delete(gem_file)
      puts "  Deleted: #{gem_file}"
    end
    puts "✅ Clean complete"
  end
end

# ---------------------------------------------------------------------------
# Cucumber acceptance tests
# ---------------------------------------------------------------------------
begin
  require "cucumber/rake/task"

  namespace :cucumber do
    desc "Run all Cucumber acceptance tests"
    Cucumber::Rake::Task.new(:all) do |t|
      t.cucumber_opts = ["--format", "progress", "features/"]
    end

    desc "Run only @wip (known-bug) Cucumber scenarios"
    Cucumber::Rake::Task.new(:wip) do |t|
      t.cucumber_opts = ["--tags", "@wip", "--format", "progress", "features/"]
    end

    desc "Run passing Cucumber scenarios (exclude @wip)"
    Cucumber::Rake::Task.new(:passing) do |t|
      t.cucumber_opts = ["--tags", "not @wip", "--format", "progress", "features/"]
    end
  end

  desc "Run all Cucumber acceptance tests (alias for cucumber:all)"
  task cucumber: "cucumber:all"

rescue LoadError
  desc "Cucumber not available — install with: bundle install --with development"
  task :cucumber do
    warn "Cucumber gem is not available. Run: bundle install --with development"
  end
end
