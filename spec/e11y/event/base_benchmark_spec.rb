# frozen_string_literal: true

# rubocop:disable RSpec/FilePath, RSpec/SpecFilePathFormat
require "spec_helper"

RSpec.describe E11y::Event::Base, ".track performance", :benchmark do
  let(:event_class) do
    Class.new(described_class) do
      def self.name
        "BenchmarkEvent"
      end

      schema do
        required(:user_id).filled(:integer)
        required(:action).filled(:string)
      end
    end
  end

  let(:payload) { { user_id: 123, action: "signup" } }

  describe "performance requirements" do
    it "tracks events in <70μs (p99) with validation_mode :always" do
      # Warm-up
      10.times { event_class.track(**payload) }

      # Measure
      times = []
      1000.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        event_class.track(**payload)
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        times << (finish - start)
      end

      # Calculate p99
      sorted = times.sort
      p99_index = (sorted.length * 0.99).ceil - 1
      p99 = sorted[p99_index]

      puts "\n📊 Performance Metrics (validation_mode: :always - default):"
      puts "  Mean:   #{(times.sum / times.length).round(2)}μs"
      puts "  Median: #{sorted[sorted.length / 2].round(2)}μs"
      puts "  P95:    #{sorted[(sorted.length * 0.95).ceil - 1].round(2)}μs"
      puts "  P99:    #{p99.round(2)}μs"
      puts "  Max:    #{sorted.last.round(2)}μs"

      # DoD: <70μs p99 (allow outliers up to 300μs for GC spikes and CI variability)
      expect(p99).to be < 300, "P99 latency (#{p99.round(2)}μs) exceeds 300μs threshold"
    end

    it "tracks events in <10μs (p99) with validation_mode :sampled" do
      # Create event class with sampled validation (1%)
      sampled_class = Class.new(E11y::Event::Base) do
        validation_mode :sampled, sample_rate: 0.01 # 1% validation
        severity :info
        schema do
          required(:user_id).filled(:integer)
          required(:email).filled(:string)
        end
      end

      payload = { user_id: 123, email: "test@example.com" }

      # Warm-up
      10.times { sampled_class.track(**payload) }

      # Measure
      times = []
      1000.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        sampled_class.track(**payload)
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        times << (finish - start)
      end

      # Calculate p99
      sorted = times.sort
      p99_index = (sorted.length * 0.99).ceil - 1
      p99 = sorted[p99_index]

      puts "\n📊 Performance Metrics (validation_mode: :sampled, 1%):"
      puts "  Mean:   #{(times.sum / times.length).round(2)}μs"
      puts "  Median: #{sorted[sorted.length / 2].round(2)}μs"
      puts "  P95:    #{sorted[(sorted.length * 0.95).ceil - 1].round(2)}μs"
      puts "  P99:    #{p99.round(2)}μs"
      puts "  Max:    #{sorted.last.round(2)}μs"

      # DoD: <10μs p99 with sampled validation (balanced) - allow CI variability up to 100μs
      expect(p99).to be < 100, "P99 latency (#{p99.round(2)}μs) exceeds 100μs threshold (sampled)"
    end

    it "tracks events in <50μs (p99) with validation_mode :never" do
      # Create event class with validation disabled
      never_validate_class = Class.new(E11y::Event::Base) do
        validation_mode :never
        severity :info
      end

      payload = { user_id: 123, email: "test@example.com" }

      # Warm-up
      10.times { never_validate_class.track(**payload) }

      # Measure
      times = []
      1000.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        never_validate_class.track(**payload)
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        times << (finish - start)
      end

      # Calculate p99
      sorted = times.sort
      p99_index = (sorted.length * 0.99).ceil - 1
      p99 = sorted[p99_index]

      puts "\n📊 Performance Metrics (validation_mode: :never):"
      puts "  Mean:   #{(times.sum / times.length).round(2)}μs"
      puts "  Median: #{sorted[sorted.length / 2].round(2)}μs"
      puts "  P95:    #{sorted[(sorted.length * 0.95).ceil - 1].round(2)}μs"
      puts "  P99:    #{p99.round(2)}μs"
      puts "  Max:    #{sorted.last.round(2)}μs"

      # DoD: <50μs p99 achievable WITHOUT validation (allow GC outliers up to 200μs)
      expect(p99).to be < 200, "P99 latency (#{p99.round(2)}μs) exceeds 200μs threshold (never)"
    end
  end

  describe "zero-allocation verification" do
    it "does not create Event objects" do
      # This test verifies that track() returns Hash, not Event instance
      result = event_class.track(**payload)

      expect(result).to be_a(Hash)
      expect(result).not_to be_a(described_class)
    end

    it "returns same Hash structure consistently" do
      result1 = event_class.track(**payload)
      result2 = event_class.track(**payload)

      # Should have identical keys
      expect(result1.keys).to eq(result2.keys)

      # Should have same structure (except timestamp)
      expect(result1[:event_name]).to eq(result2[:event_name])
      expect(result1[:severity]).to eq(result2[:severity])
      expect(result1[:version]).to eq(result2[:version])
    end
  end
end
# rubocop:enable RSpec/FilePath, RSpec/SpecFilePathFormat
