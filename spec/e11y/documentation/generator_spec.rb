# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "e11y/documentation/generator"

RSpec.describe E11y::Documentation::Generator do
  def make_event_class(event_name:, severity: :info, class_name: "Events::Test", compiled_schema: nil)
    Class.new do
      define_singleton_method(:name) { class_name }
      define_singleton_method(:event_name) { event_name }
      define_singleton_method(:severity) { severity }
      define_singleton_method(:compiled_schema) { compiled_schema }
    end
  end

  def make_schema_with_keys(*keys)
    key_objects = keys.map { |k| double("key", name: k) }
    double("compiled_schema", key_map: double(keys: key_objects))
  end

  describe ".generate" do
    context "with no criteria or grep" do
      let(:order_created) do
        make_event_class(
          event_name: "order.created",
          severity: :info,
          class_name: "Events::OrderCreated",
          compiled_schema: make_schema_with_keys(:order_id, :amount)
        )
      end

      let(:payment_failed) do
        make_event_class(
          event_name: "payment.failed",
          severity: :error,
          class_name: "Events::PaymentFailed",
          compiled_schema: nil
        )
      end

      before do
        allow(E11y::Registry).to receive(:event_classes).and_return([order_created, payment_failed])
      end

      it "creates README.md in output dir" do
        Dir.mktmpdir do |tmpdir|
          described_class.generate(tmpdir, criteria: {}, grep: nil)

          readme_path = File.join(tmpdir, "README.md")
          expect(File).to exist(readme_path)
        end
      end

      it "README content includes 'E11y Events' and table header" do
        Dir.mktmpdir do |tmpdir|
          described_class.generate(tmpdir, criteria: {}, grep: nil)

          readme = File.read(File.join(tmpdir, "README.md"))
          expect(readme).to include("E11y Events")
          expect(readme).to include("| Event | Class | Severity |")
        end
      end

      it "creates per-event .md file (event_name 'order.created' -> order_created.md)" do
        Dir.mktmpdir do |tmpdir|
          described_class.generate(tmpdir, criteria: {}, grep: nil)

          order_file = File.join(tmpdir, "order_created.md")
          expect(File).to exist(order_file)
        end
      end

      it "event file content includes class name and severity" do
        Dir.mktmpdir do |tmpdir|
          described_class.generate(tmpdir, criteria: {}, grep: nil)

          order_content = File.read(File.join(tmpdir, "order_created.md"))
          expect(order_content).to include("Events::OrderCreated")
          expect(order_content).to include("info")

          payment_content = File.read(File.join(tmpdir, "payment_failed.md"))
          expect(payment_content).to include("Events::PaymentFailed")
          expect(payment_content).to include("error")
        end
      end
    end

    context "with criteria filtering" do
      let(:error_event) do
        make_event_class(
          event_name: "payment.failed",
          severity: :error,
          class_name: "Events::PaymentFailed",
          compiled_schema: nil
        )
      end

      let(:info_event) do
        make_event_class(
          event_name: "order.created",
          severity: :info,
          class_name: "Events::OrderCreated",
          compiled_schema: nil
        )
      end

      it "uses Registry.where and outputs only matching events" do
        allow(E11y::Registry).to receive(:where).with(severity: :error).and_return([error_event])

        Dir.mktmpdir do |tmpdir|
          described_class.generate(tmpdir, criteria: { severity: :error }, grep: nil)

          readme = File.read(File.join(tmpdir, "README.md"))
          expect(readme).to include("payment.failed")
          expect(readme).to include("Events::PaymentFailed")
          expect(readme).not_to include("order.created")
          expect(readme).not_to include("Events::OrderCreated")

          expect(File).to exist(File.join(tmpdir, "payment_failed.md"))
          expect(File).not_to exist(File.join(tmpdir, "order_created.md"))
        end
      end
    end
  end
end
