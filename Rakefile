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
#   rake release:gem_push  # Publish e11y + e11y-devtools to RubyGems
#   rake release:build_gems # Build both .gem packages (no tests)
#   rake spec:all          # Run all test suites
#   rake spec:unit         # Run unit tests only (fast)
#   rake spec:integration  # Run integration tests
#
# See RELEASE.md for detailed release instructions

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

def e11y_devtools_specs_available?
  # Devtools specs live in monorepo; run them when the directory exists
  # (no need for gem in bundle — spec_helper loads lib via path)
  File.directory?(File.join(__dir__, "gems/e11y-devtools/spec"))
end

# Built with: (cd gems/e11y-devtools && gem build …) — .gem stays in this directory
E11Y_DEVTOOLS_GEM_DIR = File.expand_path("gems/e11y-devtools", __dir__).freeze

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

  desc "Run all tests (unit + memory + integration + railtie + cucumber)"
  task :all do
    puts "\n#{'=' * 80}"
    puts "Running UNIT tests (spec/e11y + top-level specs)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:unit"].invoke

    if e11y_devtools_specs_available?
      puts "\n#{'=' * 80}"
      puts "Running E11Y-DEVTOOLS unit tests (gems/e11y-devtools/spec/)..."
      puts "#{'=' * 80}\n"
      Rake::Task["spec:devtools"].invoke
    else
      puts "\n⏭️  Skipping e11y-devtools specs (gems/e11y-devtools/spec/ not found)"
    end

    puts "\n#{'=' * 80}"
    puts "Running MEMORY tests (allocations, leaks, consumption)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:memory"].invoke

    puts "\n#{'=' * 80}"
    puts "Running INTEGRATION tests (spec/integration)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:integration"].invoke

    puts "\n#{'=' * 80}"
    puts "Running RAILTIE tests (Rails initialization)..."
    puts "#{'=' * 80}\n"
    Rake::Task["spec:railtie"].invoke

    if Rake::Task.task_defined?("cucumber:passing")
      puts "\n#{'=' * 80}"
      puts "Running CUCUMBER tests (features/, exclude @wip)..."
      puts "#{'=' * 80}\n"
      Rake::Task["cucumber:passing"].invoke
    else
      puts "\n⚠️  Skipping Cucumber (bundle install --with development)"
    end

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

  desc "Run memory profiling specs (allocations, leaks, consumption)"
  task :memory do
    sh "bundle exec rspec " \
       "spec/e11y/memory_spec.rb " \
       "spec/e11y/event/base_benchmark_spec.rb " \
       "--tag memory --format documentation"
  end

  desc "Run e11y-devtools unit tests (gems/e11y-devtools/spec/)"
  task :devtools do
    sh "bundle exec rspec gems/e11y-devtools/spec/ --tag ~integration --format progress"
  end

  desc "Run ALL tests including benchmarks and cucumber (very slow)"
  task :everything do
    puts "\n#{'=' * 80}"
    puts "Running ALL tests (unit + integration + railtie + cucumber + benchmarks)"
    puts "#{'=' * 80}\n"
    Rake::Task["spec:unit"].invoke
    Rake::Task["spec:devtools"].invoke if e11y_devtools_specs_available?
    Rake::Task["spec:integration"].invoke
    Rake::Task["spec:railtie"].invoke
    Rake::Task["cucumber:passing"].invoke if Rake::Task.task_defined?("cucumber:passing")
    Rake::Task["spec:benchmark"].invoke
    Rake::Task["spec:memory"].invoke

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
      unreleased = "## [Unreleased]\n\n### Added\n\n### Changed\n\n### Fixed\n\n"
      unreleased += "### Deprecated\n\n### Removed\n\n### Security\n\n\\1"
      updated_changelog = updated_changelog.sub(
        /(## \[#{Regexp.escape(new_version)}\] - #{today})/,
        unreleased
      )

      File.write(changelog_file, updated_changelog)
      puts "✅ Updated CHANGELOG.md:"
      puts "   - [Unreleased] → [#{new_version}] - #{today}"
      puts "   - Added new [Unreleased] section"
    else
      # No [Unreleased] section, just add version entry

      # Find where to insert (after the header, before first version)

      if /(## \[\d+\.\d+\.\d+\])/.match?(changelog_content)
        new_section = "## [Unreleased]\n\n### Added\n\n### Changed\n\n### Fixed\n\n"
        new_section += "### Deprecated\n\n### Removed\n\n### Security\n\n"
        new_section += "## [#{new_version}] - #{today}\n\n### Added\n- Version bump\n\n\\1"
        updated_changelog = changelog_content.sub(/(## \[\d+\.\d+\.\d+\])/, new_section)
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

  desc "Build e11y and e11y-devtools .gem files (no tests; devtools built in its directory)"
  task :build_gems do
    require_relative "lib/e11y/version"
    require_relative "gems/e11y-devtools/lib/e11y/devtools/version"

    puts "\n[build] e11y v#{E11y::VERSION}..."
    unless system("gem build e11y.gemspec")
      puts "❌ Error: Failed to build e11y gem"
      exit 1
    end

    puts "\n[build] e11y-devtools v#{E11y::Devtools::VERSION}..."
    Dir.chdir(E11Y_DEVTOOLS_GEM_DIR) do
      unless system("gem build e11y-devtools.gemspec")
        puts "❌ Error: Failed to build e11y-devtools gem"
        exit 1
      end
    end

    devtools_artifact = File.join(E11Y_DEVTOOLS_GEM_DIR, "e11y-devtools-#{E11y::Devtools::VERSION}.gem")
    puts "\n✅ Built:"
    puts "   - e11y-#{E11y::VERSION}.gem"
    puts "   - #{devtools_artifact}"
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

    # Step 3: Build gems (e11y + e11y-devtools)
    puts "\n[3/5] Building gems..."
    Rake::Task["release:build_gems"].invoke
    require_relative "gems/e11y-devtools/lib/e11y/devtools/version"
    puts "✅ Gems built: e11y-#{version}.gem + e11y-devtools-#{E11y::Devtools::VERSION}.gem"

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
    puts "     rake release:gem_push"
    puts "\n"
  end

  namespace :rubygems do
    desc "Publish e11y gem only"
    task :push_core do
      require_relative "lib/e11y/version"
      gem_file = "e11y-#{E11y::VERSION}.gem"

      puts "\n#{'=' * 80}"
      puts "📤 Publishing e11y v#{E11y::VERSION} to RubyGems.org"
      puts "#{'=' * 80}\n"

      unless File.exist?(gem_file)
        puts "❌ Error: Gem file not found: #{gem_file}"
        puts "Run 'rake release:build_gems' or 'rake release:prep' first"
        exit 1
      end

      puts "This will publish #{gem_file}"
      puts "You may be prompted for RubyGems credentials and MFA."
      puts "\nContinue? (y/N)"

      response = $stdin.gets.chomp.downcase
      unless %w[y yes].include?(response)
        puts "❌ Publication cancelled"
        exit 0
      end

      unless system("gem push #{gem_file}")
        puts "\n❌ Error: Failed to publish e11y"
        exit 1
      end

      puts "\n✅ Published e11y v#{E11y::VERSION}"
      puts "Verify: https://rubygems.org/gems/e11y/versions/#{E11y::VERSION}"
    end

    desc "Publish e11y-devtools gem only"
    task :push_devtools do
      require_relative "gems/e11y-devtools/lib/e11y/devtools/version"
      version = E11y::Devtools::VERSION
      gem_file = File.join(E11Y_DEVTOOLS_GEM_DIR, "e11y-devtools-#{version}.gem")

      puts "\n#{'=' * 80}"
      puts "📤 Publishing e11y-devtools v#{version} to RubyGems.org"
      puts "#{'=' * 80}\n"

      unless File.exist?(gem_file)
        puts "❌ Error: Gem file not found: #{gem_file}"
        puts "Run 'rake release:build_gems' or 'rake release:prep' first"
        exit 1
      end

      puts "This will publish #{gem_file}"
      puts "You may be prompted for RubyGems credentials and MFA."
      puts "\nContinue? (y/N)"

      response = $stdin.gets.chomp.downcase
      unless %w[y yes].include?(response)
        puts "❌ Publication cancelled"
        exit 0
      end

      unless system("gem push #{gem_file}")
        puts "\n❌ Error: Failed to publish e11y-devtools"
        exit 1
      end

      puts "\n✅ Published e11y-devtools v#{version}"
      puts "Verify: https://rubygems.org/gems/e11y-devtools/versions/#{version}"
    end
  end

  desc "Publish e11y then e11y-devtools to RubyGems.org (requires authentication, MFA)"
  task :gem_push do
    require_relative "lib/e11y/version"
    require_relative "gems/e11y-devtools/lib/e11y/devtools/version"

    core_gem = "e11y-#{E11y::VERSION}.gem"
    devtools_gem = File.join(E11Y_DEVTOOLS_GEM_DIR, "e11y-devtools-#{E11y::Devtools::VERSION}.gem")

    puts "\n#{'=' * 80}"
    puts "📤 Publishing to RubyGems.org"
    puts "#{'=' * 80}\n"

    unless File.exist?(core_gem)
      puts "❌ Error: Gem file not found: #{core_gem}"
      puts "Run 'rake release:build_gems' or 'rake release:prep' first"
      exit 1
    end
    unless File.exist?(devtools_gem)
      puts "❌ Error: Gem file not found: #{devtools_gem}"
      puts "Run 'rake release:build_gems' or 'rake release:prep' first"
      exit 1
    end

    puts "This will publish (e11y first, then e11y-devtools):"
    puts "  1. #{core_gem}"
    puts "  2. #{devtools_gem}"
    puts "\nYou may be prompted for RubyGems credentials and MFA for each push."
    puts "\nContinue? (y/N)"

    response = $stdin.gets.chomp.downcase
    unless %w[y yes].include?(response)
      puts "❌ Publication cancelled"
      exit 0
    end

    unless system("gem push #{core_gem}")
      puts "\n❌ Error: Failed to publish e11y"
      exit 1
    end

    unless system("gem push #{devtools_gem}")
      puts "\n❌ Error: Failed to publish e11y-devtools (e11y may already be on RubyGems)"
      exit 1
    end

    puts "\n✅ Successfully published both gems!"
    puts "  e11y:         https://rubygems.org/gems/e11y/versions/#{E11y::VERSION}"
    puts "  e11y-devtools: https://rubygems.org/gems/e11y-devtools/versions/#{E11y::Devtools::VERSION}"
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
    puts "  2. Verify on RubyGems: https://rubygems.org/gems/e11y and /gems/e11y-devtools"
    puts "  3. Update README badges"
    puts "  4. Announce on social media"
    puts "\n"
  end

  desc "Clean up built gem files (repo root + gems/e11y-devtools)"
  task :clean do
    puts "🧹 Cleaning up gem files..."
    FileList["*.gem"].each do |gem_file|
      File.delete(gem_file)
      puts "  Deleted: #{gem_file}"
    end
    FileList[File.join(E11Y_DEVTOOLS_GEM_DIR, "*.gem")].each do |gem_file|
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
      # Quote tag expression so shell keeps "not @wip" as one arg (Cucumber::Rake::Task uses cmd.join(' '))
      t.cucumber_opts = ["--tags", '"not @wip"', "--format", "progress", "features/"]
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
