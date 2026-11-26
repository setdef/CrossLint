# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class SignatureCommentsTaskTest < Minitest::Test
  COMMENTED = <<~RBS
    # The module.
    module CrossLint
      # The class.
      class Thing
        # The limit.
        LIMIT: Integer

        # The name.
        attr_reader name: String

        # Runs.
        def run: () -> void

        private

        def hidden: () -> void
      end

      # The interface.
      interface _Port
        # Calls.
        def call: () -> void
      end
    end
  RBS

  def setup
    @root = Dir.mktmpdir("crosslint")
    # The task finds sig/ beside its own tasks/ folder, so it runs from a copy.
    FileUtils.mkdir_p(File.join(@root, "tasks"))
    FileUtils.cp(File.join(ROOT, "tasks/signature_comments.rb"), File.join(@root, "tasks"))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_passes_a_tree_where_every_public_declaration_has_a_comment
    write(@root, "sig/cross_lint/thing.rbs", COMMENTED)

    assert_equal ["", 0], run_task
  end

  def test_reports_a_method_with_no_comment
    assert_reports "sig/cross_lint/thing.rbs:11: CrossLint::Thing#run has no comment", COMMENTED.sub("  # Runs.\n", "")
  end

  def test_reports_an_attribute_with_no_comment
    assert_reports "sig/cross_lint/thing.rbs:8: CrossLint::Thing#name has no comment", COMMENTED.sub("  # The name.\n", "")
  end

  def test_reports_a_constant_with_no_comment
    assert_reports "sig/cross_lint/thing.rbs:5: CrossLint::Thing::LIMIT has no comment", COMMENTED.sub("  # The limit.\n", "")
  end

  def test_reports_an_interface_with_no_comment
    assert_reports "sig/cross_lint/thing.rbs:19: CrossLint::_Port has no comment", COMMENTED.sub("  # The interface.\n", "")
  end

  private

  def assert_reports(line, source)
    write(@root, "sig/cross_lint/thing.rbs", source)
    output, status = run_task

    assert_equal ["rake rbs:comments: #{line}\n", 1], [output, status]
  end

  def run_task
    output, status = Open3.capture2e(RbConfig.ruby, File.join(@root, "tasks/signature_comments.rb"))
    [output, status.exitstatus]
  end
end
