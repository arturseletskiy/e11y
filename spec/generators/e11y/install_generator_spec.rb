# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/e11y/install/install_generator"
require "fileutils"
require "minitest"

RSpec.describe E11y::Generators::InstallGenerator, type: :generator do
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
  destination File.expand_path("../../../tmp/generators/install", __dir__)

  before do
    self.assertions = 0
    prepare_destination
  end

  describe "config/initializers/e11y.rb" do
    it "creates the initializer file" do
      run_generator
      assert_file "config/initializers/e11y.rb"
    end

    it "initializer contains E11y.configure block" do
      run_generator
      assert_file "config/initializers/e11y.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/E11y\.configure do \|config\|/)
      end
    end

    it "initializer mentions adapters configuration" do
      run_generator
      assert_file "config/initializers/e11y.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/adapters/)
      end
    end

    it "initializer mentions pii_filtering configuration" do
      run_generator
      assert_file "config/initializers/e11y.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/pii_filtering/)
      end
    end

    it "initializer mentions ephemeral_buffer configuration" do
      run_generator
      assert_file "config/initializers/e11y.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/ephemeral_buffer/)
      end
    end

    it "initializer mentions rate_limiting configuration" do
      run_generator
      assert_file "config/initializers/e11y.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/rate_limiting/)
      end
    end

    it "initializer mentions E11y.start!" do
      run_generator
      assert_file "config/initializers/e11y.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/E11y\.start!/)
      end
    end

    it "initializer has frozen string literal comment" do
      run_generator
      assert_file "config/initializers/e11y.rb" do |content|
        expect(content.force_encoding("UTF-8")).to match(/# frozen_string_literal: true/)
      end
    end
  end

  describe "app/events directory" do
    it "creates app/events directory" do
      run_generator
      assert_directory "app/events"
    end
  end
end
