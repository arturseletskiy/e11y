# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/e11y/event/event_generator"
require "fileutils"
require "minitest"

RSpec.describe E11y::Generators::EventGenerator, type: :generator do
  include FileUtils
  include Minitest::Assertions
  include Rails::Generators::Testing::Assertions
  include Rails::Generators::Testing::Behavior

  attr_accessor :assertions

  # assert_nothing_raised was removed in Minitest 5; define a passthrough so
  # Rails::Generators::Testing::Assertions#assert_file (which calls it) works.
  def assert_nothing_raised
    yield
  end

  tests described_class
  destination File.expand_path("../../../tmp/generators/event", __dir__)

  before do
    self.assertions = 0
    prepare_destination
  end

  describe "with argument 'order_created'" do
    it "creates app/events/events/order_created.rb" do
      run_generator ["order_created"]
      assert_file "app/events/events/order_created.rb"
    end

    it "created file inherits from E11y::Event::Base" do
      run_generator ["order_created"]
      assert_file "app/events/events/order_created.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/< E11y::Event::Base/)
      end
    end

    it "created file has correct class name OrderCreated" do
      run_generator ["order_created"]
      assert_file "app/events/events/order_created.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/class OrderCreated/)
      end
    end

    it "created file is wrapped in Events module" do
      run_generator ["order_created"]
      assert_file "app/events/events/order_created.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/module Events/)
      end
    end

    it "created file contains schema block" do
      run_generator ["order_created"]
      assert_file "app/events/events/order_created.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/schema do/)
      end
    end

    it "created file has frozen string literal comment" do
      run_generator ["order_created"]
      assert_file "app/events/events/order_created.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/# frozen_string_literal: true/)
      end
    end
  end

  describe "with CamelCase argument 'OrderPaid'" do
    it "creates app/events/events/order_paid.rb (underscored filename)" do
      run_generator ["OrderPaid"]
      assert_file "app/events/events/order_paid.rb"
    end

    it "created file has class name OrderPaid" do
      run_generator ["OrderPaid"]
      assert_file "app/events/events/order_paid.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/class OrderPaid/)
      end
    end
  end

  describe "with namespaced argument 'payments/charge_failed'" do
    # The generator uses file_name (last segment only) for the output path,
    # so 'payments/charge_failed' creates charge_failed.rb (not payments/charge_failed.rb).
    it "creates app/events/events/charge_failed.rb" do
      run_generator ["payments/charge_failed"]
      assert_file "app/events/events/charge_failed.rb"
    end

    it "created file has class name Payments::ChargeFailed" do
      run_generator ["payments/charge_failed"]
      assert_file "app/events/events/charge_failed.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/class Payments::ChargeFailed/)
      end
    end
  end

  describe "when name argument is not provided" do
    it "raises Thor::RequiredArgumentMissingError" do
      # run_generator uses capture(:stdout) which swallows the error;
      # call generator_class.new directly to get the exception.
      expect { generator_class.new([], {}, {}) }
        .to raise_error(Thor::RequiredArgumentMissingError, /name/)
    end
  end
end
