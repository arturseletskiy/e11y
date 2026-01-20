# frozen_string_literal: true

require "spec_helper"
require "e11y/sampling/stratified_tracker"
require "e11y/slo/tracker"

RSpec.describe "Stratified Sampling for SLO Accuracy (C11 Resolution)" do
  let(:tracker) { E11y::Sampling::StratifiedTracker.new }

  describe "SLO accuracy with sampling" do
    it "maintains <5% error with stratified sampling" do
      # Simulate HTTP requests: 90% success (10% sampling), 10% error (100% sampling)
      # Total: 1000 events
      900.times do
        sampled = rand < 0.1
        tracker.record_sample(severity: :success, sample_rate: 0.1, sampled: sampled)
      end

      100.times do
        tracker.record_sample(severity: :error, sample_rate: 1.0, sampled: true)
      end

      # Get observed counts (sampled)
      success_stats = tracker.stratum_stats(:success)
      error_stats = tracker.stratum_stats(:error)

      observed_success = success_stats[:sampled_count]
      observed_errors = error_stats[:sampled_count]

      # Apply sampling correction
      success_correction = tracker.sampling_correction(:success)
      error_correction = tracker.sampling_correction(:error)

      estimated_success = observed_success * success_correction
      estimated_errors = observed_errors * error_correction

      # Calculate estimated success rate
      estimated_total = estimated_success + estimated_errors
      estimated_success_rate = estimated_success / estimated_total

      # True success rate: 90%
      true_success_rate = 0.9

      # Verify accuracy: <5% error
      error_pct = ((estimated_success_rate - true_success_rate).abs / true_success_rate) * 100
      expect(error_pct).to be < 5.0
    end

    it "handles varying sampling rates" do
      # Success events: mix of 10%, 20%, 30% sampling
      300.times { tracker.record_sample(severity: :success, sample_rate: 0.1, sampled: rand < 0.1) }
      300.times { tracker.record_sample(severity: :success, sample_rate: 0.2, sampled: rand < 0.2) }
      300.times { tracker.record_sample(severity: :success, sample_rate: 0.3, sampled: rand < 0.3) }

      # Errors: 100% sampling
      100.times { tracker.record_sample(severity: :error, sample_rate: 1.0, sampled: true) }

      # Correction should be ~5 (average of 10, 5, 3.33)
      success_correction = tracker.sampling_correction(:success)
      expect(success_correction).to be_between(4, 6)

      error_correction = tracker.sampling_correction(:error)
      expect(error_correction).to eq(1.0)
    end
  end

  describe "ADR-009 §3.7 compliance" do
    it "implements stratified sampling for SLO accuracy" do
      # Different sampling rates per severity
      tracker.record_sample(severity: :success, sample_rate: 0.1, sampled: true)
      tracker.record_sample(severity: :error, sample_rate: 1.0, sampled: true)

      # Corrections reflect sampling rates
      expect(tracker.sampling_correction(:success)).to eq(10.0)
      expect(tracker.sampling_correction(:error)).to eq(1.0)
    end
  end

  describe "UC-014 production example" do
    it "corrects SLO metrics under load-based adaptive sampling" do
      # During high load: success events sampled at 10%
      100.times do
        tracker.record_sample(
          severity: :success,
          sample_rate: 0.1,
          sampled: rand < 0.1
        )
      end

      # Errors always sampled
      10.times do
        tracker.record_sample(
          severity: :error,
          sample_rate: 1.0,
          sampled: true
        )
      end

      # Calculate corrected SLO
      success_stats = tracker.stratum_stats(:success)
      error_stats = tracker.stratum_stats(:error)

      corrected_success = success_stats[:sampled_count] * tracker.sampling_correction(:success)
      corrected_errors = error_stats[:sampled_count] * tracker.sampling_correction(:error)

      corrected_total = corrected_success + corrected_errors
      corrected_success_rate = corrected_success / corrected_total

      # True success rate: ~91% (100/(100+10))
      # Note: With randomized sampling, expect wider tolerance
      expect(corrected_success_rate).to be_between(0.80, 0.95) # Reasonable range given sampling variance
    end
  end

  describe "C11 Resolution verification" do
    it "resolves C11: Sampling bias in SLO metrics" do
      # Before C11: Naive sampling → biased SLO (errors overrepresented)
      # After C11: Stratified sampling → accurate SLO

      # Generate events with different sampling rates
      1000.times { tracker.record_sample(severity: :success, sample_rate: 0.05, sampled: rand < 0.05) }
      50.times { tracker.record_sample(severity: :error, sample_rate: 1.0, sampled: true) }

      # Naive calculation (without correction)
      success_observed = tracker.stratum_stats(:success)[:sampled_count]
      error_observed = tracker.stratum_stats(:error)[:sampled_count]
      naive_total = success_observed + error_observed
      naive_success_rate = success_observed.to_f / naive_total

      # Corrected calculation (with C11 resolution)
      success_corrected = success_observed * tracker.sampling_correction(:success)
      error_corrected = error_observed * tracker.sampling_correction(:error)
      corrected_total = success_corrected + error_corrected
      corrected_success_rate = success_corrected / corrected_total

      # True success rate: 95.2% (1000/(1000+50))
      true_rate = 1000.0 / 1050.0

      # Corrected should be much closer to true rate than naive
      naive_error = (naive_success_rate - true_rate).abs
      corrected_error = (corrected_success_rate - true_rate).abs

      expect(corrected_error).to be < naive_error
      expect(corrected_error / true_rate).to be < 0.05 # <5% relative error
    end
  end
end
