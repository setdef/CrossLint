# frozen_string_literal: true

require "test_helper"
require_relative "../../tasks/gate_subjects"

class GateSubjectsTest < Minitest::Test
  ALL = %w[CrossLint::Core::LoadProject#call CrossLint::Core::LoadProjectFiles.new CrossLint::Core::Check#run CrossLint::App#run CrossLint::CLI#run CrossLint::CLIHelp.new CrossLint::KDL::Parse#call].freeze
  CONFIGURED = ["CrossLint*", "source:plugins/*/*.rb", "source:plugins/*/rules/*.rb"].freeze

  def test_a_file_under_test_is_a_test_file
    assert GateSubjects.test_file?("test/cross_lint/app_test.rb")
    assert GateSubjects.test_file?("test/test_helper.rb")
    assert GateSubjects.test_file?("plugins/alpha/test/fixture_test.rb")
  end

  def test_other_files_are_not_test_files
    refute GateSubjects.test_file?("lib/cross_lint/app.rb")
    refute GateSubjects.test_file?("plugins/alpha/artifacts.rb")
    refute GateSubjects.test_file?("Rakefile")
  end

  def test_a_test_of_a_script_is_no_test_of_a_subject
    refute GateSubjects.test_file?("test/tasks/doctest_test.rb")
    refute GateSubjects.test_file?("test/github/check_ci_passed_test.rb")
  end

  def test_a_test_path_names_the_classes_it_covers
    assert_equal "crosslint::core::loadproject", GateSubjects.class_prefix("test/cross_lint/core/load_project_test.rb")
    assert_equal "crosslint::app", GateSubjects.class_prefix("test/cross_lint/app_test.rb")
  end

  def test_a_file_not_named_like_a_test_names_no_classes
    assert_nil GateSubjects.class_prefix("test/test_helper.rb")
    assert_nil GateSubjects.class_prefix("test/fixtures/tool.usage.kdl")
  end

  def test_a_plugin_test_names_its_plugin
    assert_equal "alpha", GateSubjects.plugin_name("plugins/alpha/test/fixture_test.rb")
    assert_nil GateSubjects.plugin_name("test/cross_lint/app_test.rb")
  end

  def test_a_plugin_has_the_source_expressions_of_the_configuration
    assert_equal ["source:plugins/alpha/*.rb", "source:plugins/alpha/rules/*.rb"], GateSubjects.plugin_expressions(CONFIGURED, "alpha")
  end

  def test_a_test_covers_the_subjects_its_path_names
    covered, unmapped = GateSubjects.covered(["test/cross_lint/core/load_project_test.rb", "lib/cross_lint/app.rb"], ALL, CONFIGURED, ->(_) { flunk })

    assert_equal %w[CrossLint::Core::LoadProject#call CrossLint::Core::LoadProjectFiles.new], covered
    assert_empty unmapped
  end

  def test_a_test_covers_the_subjects_of_an_acronym_whatever_its_case
    covered, unmapped = GateSubjects.covered(["test/cross_lint/cli_test.rb", "test/cross_lint/kdl/parse_test.rb"], ALL, CONFIGURED, ->(_) { flunk })

    assert_equal %w[CrossLint::CLI#run CrossLint::CLIHelp.new CrossLint::KDL::Parse#call], covered
    assert_empty unmapped
  end

  def test_a_plugin_test_covers_the_subjects_of_its_plugin
    asked = []
    list = ->(expressions) { asked << expressions && %w[Artifacts#role] }
    covered, unmapped = GateSubjects.covered(["plugins/alpha/test/paths_test.rb"], ALL, CONFIGURED, list)

    assert_equal %w[Artifacts#role], covered
    assert_empty unmapped
    assert_equal [["source:plugins/alpha/*.rb", "source:plugins/alpha/rules/*.rb"]], asked
  end

  def test_a_test_that_covers_no_subject_is_unmapped
    files = ["test/cross_lint/adapters/report_test.rb", "test/test_helper.rb", "plugins/debt/test/x_test.rb"]
    covered, unmapped = GateSubjects.covered(files, ALL, CONFIGURED, ->(_) { [] })

    assert_empty covered
    assert_equal files, unmapped
  end

  def test_a_plugin_with_no_source_expression_is_unmapped
    covered, unmapped = GateSubjects.covered(["plugins/debt/test/x_test.rb"], ALL, ["CrossLint*"], ->(_) { flunk })

    assert_empty covered
    assert_equal ["plugins/debt/test/x_test.rb"], unmapped
  end
end
