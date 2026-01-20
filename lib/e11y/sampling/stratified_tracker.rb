# frozen_string_literal: true

module E11y
  module Sampling
    # Stratified Sampling Tracker for SLO accuracy (FEAT-4851, C11 Resolution)
    #
    # Tracks sampling statistics per severity stratum to enable sampling correction
    # in SLO calculations. Ensures accurate SLO metrics even with aggressive sampling.
    #
    # @example Usage in sampling middleware
    #   tracker = StratifiedTracker.new
    #   tracker.record_sample(severity: :success, sample_rate: 0.1, sampled: true)
    #   tracker.record_sample(severity: :error, sample_rate: 1.0, sampled: true)
    #
    #   correction = tracker.sampling_correction(:success) # => 10.0 (1/0.1)
    #
    # @see ADR-009 §3.7 Stratified Sampling for SLO Accuracy
    # @see UC-014 Adaptive Sampling (C11 Resolution)
    class StratifiedTracker
      # @return [Hash{Symbol => Hash}] Stratum statistics
      attr_reader :strata

      def initialize
        @strata = Hash.new { |h, k| h[k] = { sampled_count: 0, total_count: 0, sample_rate_sum: 0.0 } }
        @mutex = Mutex.new
      end

      # Record a sampling decision for a severity stratum
      #
      # @param severity [Symbol] Event severity (:debug, :info, :success, :warn, :error, :fatal)
      # @param sample_rate [Float] Sample rate used (0.0-1.0)
      # @param sampled [Boolean] Whether event was sampled
      # @return [void]
      def record_sample(severity:, sample_rate:, sampled:)
        @mutex.synchronize do
          stratum = @strata[severity]
          stratum[:total_count] += 1
          stratum[:sampled_count] += 1 if sampled
          stratum[:sample_rate_sum] += sample_rate
        end
      end

      # Get sampling correction factor for a severity
      #
      # Correction factor = 1 / sample_rate
      # Multiply observed counts by this to estimate true counts.
      #
      # @param severity [Symbol] Event severity
      # @return [Float] Correction factor (1.0 if no samples)
      def sampling_correction(severity)
        @mutex.synchronize do
          stratum = @strata[severity]
          return 1.0 if stratum[:sampled_count].zero?

          # Average sample rate for this stratum
          avg_sample_rate = stratum[:sample_rate_sum] / stratum[:total_count]
          return 1.0 if avg_sample_rate.zero?

          1.0 / avg_sample_rate
        end
      end

      # Get statistics for a severity stratum
      #
      # @param severity [Symbol] Event severity
      # @return [Hash] Stratum statistics
      def stratum_stats(severity)
        @mutex.synchronize do
          @strata[severity].dup
        end
      end

      # Get statistics for all strata
      #
      # @return [Hash{Symbol => Hash}] All stratum statistics
      def all_strata_stats
        @mutex.synchronize do
          @strata.transform_values(&:dup)
        end
      end

      # Reset all statistics
      #
      # @return [void]
      def reset!
        @mutex.synchronize do
          @strata.clear
        end
      end
    end
  end
end
