# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Instruments::Sidekiq do
  describe "ClientMiddleware" do
    let(:middleware) { described_class::ClientMiddleware.new }
    let(:job) { {} }

    before { E11y::Current.reset }

    describe "C17 Hybrid Tracing: Propagate parent trace context" do
      it "injects parent_trace_id from E11y::Current.trace_id" do
        E11y::Current.trace_id = "trace123"
        middleware.call(nil, job, nil, nil) {} # rubocop:todo Lint/EmptyBlock
        # C17: Propagates current trace_id as PARENT for the job
        expect(job["e11y_parent_trace_id"]).to eq("trace123")
      ensure
        E11y::Current.reset
      end

      it "injects parent_span_id from E11y::Current.span_id" do
        E11y::Current.span_id = "span123"
        middleware.call(nil, job, nil, nil) {} # rubocop:todo Lint/EmptyBlock
        # C17: Propagates current span_id as PARENT for the job
        expect(job["e11y_parent_span_id"]).to eq("span123")
      ensure
        E11y::Current.reset
      end

      it "does not inject metadata if E11y::Current is empty" do
        middleware.call(nil, job, nil, nil) {} # rubocop:todo Lint/EmptyBlock
        expect(job).not_to have_key("e11y_parent_trace_id")
        expect(job).not_to have_key("e11y_parent_span_id")
      end

      it "documents C17 behavior: propagate trace as parent (job will generate NEW trace)" do
        # C17 Hybrid Tracing: Job creates NEW trace_id, but preserves parent link
        E11y::Current.trace_id = "parent_trace_from_request"

        middleware.call(nil, job, nil, nil) {} # rubocop:todo Lint/EmptyBlock

        # Parent trace is propagated (job will know its origin)
        expect(job["e11y_parent_trace_id"]).to eq("parent_trace_from_request")
        # Job will generate NEW trace_id during execution (not set here)
      ensure
        E11y::Current.reset
      end
    end
  end

  describe "ServerMiddleware" do
    let(:middleware) { described_class::ServerMiddleware.new }
    let(:worker) { double("worker") }
    let(:job) { { "jid" => "job123" } }
    let(:queue) { "default" }

    before do
      E11y.configure do |config|
        config.request_buffer.enabled = false # Disable buffer for simpler tests
      end
    end

    after do
      E11y::Current.reset
    end

    describe "C17 Hybrid Tracing: NEW trace_id per job" do
      it "generates new trace_id for job (not reuse parent)" do
        job["e11y_parent_trace_id"] = "parent_trace123"

        middleware.call(worker, job, queue) do
          expect(E11y::Current.trace_id).not_to be_nil
          expect(E11y::Current.trace_id).not_to eq("parent_trace123")
          expect(E11y::Current.trace_id.length).to eq(32) # 16 bytes hex
        end
      end

      it "preserves parent_trace_id link to parent request" do
        job["e11y_parent_trace_id"] = "parent_trace123"

        middleware.call(worker, job, queue) do
          expect(E11y::Current.parent_trace_id).to eq("parent_trace123")
        end
      end

      it "generates trace_id even without parent_trace_id" do
        middleware.call(worker, job, queue) do
          expect(E11y::Current.trace_id).not_to be_nil
          expect(E11y::Current.trace_id.length).to eq(32)
          expect(E11y::Current.parent_trace_id).to be_nil
        end
      end

      it "generates new span_id for job" do
        middleware.call(worker, job, queue) do
          expect(E11y::Current.span_id).not_to be_nil
          expect(E11y::Current.span_id.length).to eq(16) # 8 bytes hex
        end
      end

      it "sets request_id from job jid" do
        middleware.call(worker, job, queue) do
          expect(E11y::Current.request_id).to eq("job123")
        end
      end
    end

    describe "C18 Non-Failing Event Tracking: fail_on_error = false" do
      it "sets fail_on_error to false before job execution" do
        original_setting = E11y.config.error_handling.fail_on_error

        middleware.call(worker, job, queue) do
          # Inside job context: fail_on_error should be false
          expect(E11y.config.error_handling.fail_on_error).to be false
        end

        # Restore original setting after job
        expect(E11y.config.error_handling.fail_on_error).to eq(original_setting)
      end

      it "restores original fail_on_error setting after job" do
        E11y.config.error_handling.fail_on_error = true
        expect(E11y.config.error_handling.fail_on_error).to be true

        middleware.call(worker, job, queue) {} # rubocop:todo Lint/EmptyBlock

        expect(E11y.config.error_handling.fail_on_error).to be true
      end

      it "restores fail_on_error even if job raises exception" do
        E11y.config.error_handling.fail_on_error = true

        expect do
          middleware.call(worker, job, queue) do
            raise StandardError, "Job failed"
          end
        end.to raise_error(StandardError, "Job failed")

        # Setting should be restored despite exception
        expect(E11y.config.error_handling.fail_on_error).to be true
      end

      it "documents that E11y errors won't fail jobs when fail_on_error=false" do
        # This test documents the expected behavior:
        # When fail_on_error=false (in job context), E11y adapter errors
        # should be swallowed and NOT cause job to fail.
        #
        # See ADR-013 §3.6 (C18 Resolution) for rationale.

        middleware.call(worker, job, queue) do
          expect(E11y.config.error_handling.fail_on_error).to be false
          # In this context, adapter failures should be swallowed
        end
      end
    end

    describe "Context cleanup" do
      it "resets E11y::Current after job execution" do
        middleware.call(worker, job, queue) do
          # Context is set during job
          expect(E11y::Current.trace_id).not_to be_nil
        end

        # Context is reset after job
        expect(E11y::Current.trace_id).to be_nil
        expect(E11y::Current.span_id).to be_nil
        expect(E11y::Current.parent_trace_id).to be_nil
        expect(E11y::Current.request_id).to be_nil
      end

      it "resets context even if job raises exception" do
        expect do
          middleware.call(worker, job, queue) do
            raise StandardError, "Job failed"
          end
        end.to raise_error(StandardError)

        # Context should be reset despite exception
        expect(E11y::Current.trace_id).to be_nil
        expect(E11y::Current.span_id).to be_nil
      end
    end

    describe "Error handling: E11y errors don't fail jobs" do
      before do
        E11y.configure do |config|
          config.request_buffer.enabled = true
        end
      end

      it "swallows E11y::Buffers::RequestScopedBuffer errors" do
        allow(E11y::Buffers::RequestScopedBuffer).to receive(:start!).and_raise(StandardError, "Buffer error")

        # Job should succeed despite E11y buffer failure
        expect do
          middleware.call(worker, job, queue) {} # rubocop:todo Lint/EmptyBlock
        end.not_to raise_error
      end

      it "swallows E11y::Buffers::RequestScopedBuffer.flush! errors" do
        allow(E11y::Buffers::RequestScopedBuffer).to receive(:flush!).and_raise(StandardError, "Flush error")

        # Job should succeed despite E11y flush failure
        expect do
          middleware.call(worker, job, queue) {} # rubocop:todo Lint/EmptyBlock
        end.not_to raise_error
      end

      it "swallows E11y::Current.reset errors (extreme edge case)" do
        # Mock reset to raise error only ONCE (first call in middleware)
        call_count = 0
        allow(E11y::Current).to receive(:reset) do
          call_count += 1
          raise StandardError, "Reset error" if call_count == 1

          # Second call (in after block) should work
          E11y::Current.instance_variable_set(:@attributes, {})
        end

        # Job should succeed despite E11y reset failure
        expect do
          middleware.call(worker, job, queue) {} # rubocop:todo Lint/EmptyBlock
        end.not_to raise_error
      end
    end
  end
end
