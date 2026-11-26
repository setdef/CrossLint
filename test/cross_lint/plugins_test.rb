# frozen_string_literal: true

require "test_helper"

# Mutant loads only the tests in test/, and each built-in plugin's tests
# are in its own folder, so this loads them.
Dir.glob("plugins/*/test/**/*_test.rb", base: TestHelper::ROOT).reject { |test| test.include?("/node_modules/") }
  .each { |test| require File.join(TestHelper::ROOT, test) }
