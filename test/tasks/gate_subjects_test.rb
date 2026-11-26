# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../../tasks/gate_subjects"

class GateSubjectsTest < Minitest::Test
  ALL = %w[
    CrossLint::Core::LoadProject#call CrossLint::Core::LoadProjectFiles.new CrossLint::Core::Check#run CrossLint::App#run
    CrossLint::CLI#run CrossLint::CLIHelp.new CrossLint::KDL::Parse#call
    CrossLint::Adapters::TSVDebtFiles#read CrossLint::Adapters::MemoryDebtFiles#read CrossLint::Adapters::MemoryDebtFiles#write
    CrossLint::Adapters::MemoryReport#show CrossLint::Adapters::TextReport#show
    CrossLint::Core::Condition::All#met CrossLint::Core::Spelling.new CrossLint::Artifacts#role
  ].freeze
  CONFIGURED = ["CrossLint*", "source:plugins/*/*.rb", "source:plugins/*/rules/*.rb"].freeze

  def no_list
    ->(_) { flunk "no plugin test is changed" }
  end

  # A reader of test files that holds the text of each, by path.
  def reading(texts)
    ->(path) { texts.fetch(path) }
  end

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

  def test_the_references_of_a_test_are_the_constants_its_text_names
    source = "CrossLint::Adapters::ProcessHelpers::TREE\nCore::Mistake.new\nputs Spelling\n"

    expected = %w[CrossLint::Adapters::ProcessHelpers CrossLint::Adapters::ProcessHelpers::TREE Core::Mistake Spelling]

    assert_equal expected.sort, GateSubjects.references(source).sort
  end

  def test_a_namespace_alone_is_no_reference
    assert_empty GateSubjects.references("CrossLint::Core\nCrossLint::Adapters\nCrossLint::Testing\n")
  end

  def test_a_subject_belongs_to_its_class
    assert_equal "CrossLint::CLI", GateSubjects.subject_class("CrossLint::CLI#run")
    assert_equal "CrossLint::CLIHelp", GateSubjects.subject_class("CrossLint::CLIHelp.new")
  end

  def test_a_test_covers_the_subjects_its_path_names
    path = "test/cross_lint/core/load_project_test.rb"
    covered, unmapped = GateSubjects.covered([path, "lib/cross_lint/app.rb"], ALL, CONFIGURED, no_list, read: reading(path => "# nothing\n"))

    assert_equal %w[CrossLint::Core::LoadProject#call CrossLint::Core::LoadProjectFiles.new], covered
    assert_empty unmapped
  end

  def test_a_test_covers_the_subjects_of_an_acronym_whatever_its_case
    paths = ["test/cross_lint/cli_test.rb", "test/cross_lint/kdl/parse_test.rb"]
    covered, unmapped = GateSubjects.covered(paths, ALL, CONFIGURED, no_list, read: reading(paths.to_h { |path| [path, ""] }))

    assert_equal %w[CrossLint::CLI#run CrossLint::CLIHelp.new CrossLint::KDL::Parse#call], covered
    assert_empty unmapped
  end

  def test_a_contract_test_covers_every_adapter_it_runs_the_contract_against
    path = "test/cross_lint/adapters/debt_files_test.rb"
    text = <<~RUBY
      class MemoryDebtFilesTest < Minitest::Test
        include CrossLint::Testing::DebtFilesContract
        def build = CrossLint::Adapters::MemoryDebtFiles.new
      end
      class TSVDebtFilesTest < Minitest::Test
        include CrossLint::Testing::DebtFilesContract
        def build = CrossLint::Adapters::TSVDebtFiles.new(root)
      end
    RUBY
    covered, unmapped = GateSubjects.covered([path], ALL, CONFIGURED, no_list, read: reading(path => text))

    assert_equal %w[CrossLint::Adapters::TSVDebtFiles#read CrossLint::Adapters::MemoryDebtFiles#read CrossLint::Adapters::MemoryDebtFiles#write].sort, covered.sort
    assert_empty unmapped
  end

  def test_a_report_contract_test_covers_each_report
    path = "test/cross_lint/adapters/report_test.rb"
    text = "CrossLint::Adapters::TextReport.new(out)\nCrossLint::Adapters::MemoryReport.new\nCrossLint::Testing::ReportContract\n"
    covered, unmapped = GateSubjects.covered([path], ALL, CONFIGURED, no_list, read: reading(path => text))

    assert_equal %w[CrossLint::Adapters::MemoryReport#show CrossLint::Adapters::TextReport#show], covered.sort
    assert_empty unmapped
  end

  def test_a_test_covers_the_value_classes_it_names_whether_or_not_it_qualifies_them
    path = "test/cross_lint/core/values_test.rb"
    text = "Core::Condition::All.new\nSpelling.new\nCore::Unknown.new\n"
    covered, unmapped = GateSubjects.covered([path], ALL, CONFIGURED, no_list, read: reading(path => text))

    assert_equal %w[CrossLint::Core::Condition::All#met CrossLint::Core::Spelling.new], covered.sort
    assert_empty unmapped
  end

  def test_a_test_covers_a_class_outside_the_core_namespace_it_names
    path = "test/cross_lint/core/artifacts_test.rb"
    covered, unmapped = GateSubjects.covered([path], ALL, CONFIGURED, no_list, read: reading(path => "CrossLint::Artifacts.new\n"))

    assert_equal %w[CrossLint::Artifacts#role], covered
    assert_empty unmapped
  end

  def test_a_test_does_not_cover_a_class_whose_name_only_contains_a_name_it_refers_to
    path = "test/cross_lint/core/path_test.rb"
    covered, = GateSubjects.covered([path], ALL, CONFIGURED, no_list, read: reading(path => "Load\nCheckResult\nTSV\n"))

    assert_empty covered
  end

  def test_a_plugin_test_covers_the_subjects_of_its_plugin
    asked = []
    list = ->(expressions) { asked << expressions && %w[Artifacts#role] }
    covered, unmapped = GateSubjects.covered(["plugins/alpha/test/paths_test.rb"], ALL, CONFIGURED, list)

    assert_equal %w[Artifacts#role], covered
    assert_empty unmapped
    assert_equal [["source:plugins/alpha/*.rb", "source:plugins/alpha/rules/*.rb"]], asked
  end

  def test_a_test_of_code_mutant_does_not_run_selects_no_subject_and_says_so
    path = "test/cross_lint/adapters/job_object_test.rb"
    out = StringIO.new
    covered, unmapped = GateSubjects.covered([path], ALL, CONFIGURED, no_list, read: ->(_) { flunk "its text is not read" }, out: out)

    assert_empty covered
    assert_empty unmapped
    assert_equal "rake gate:mutant: #{path} tests only code that mutant doesn't run, so it selects no subject\n", out.string
  end

  def test_a_test_that_cuts_across_the_code_is_unmapped
    files = %w[test/cross_lint/architecture_test.rb test/cross_lint/exe_test.rb test/cross_lint/plugins_test.rb test/isolation_test.rb test/test_helper.rb]
    covered, unmapped = GateSubjects.covered(files, ALL, CONFIGURED, no_list, read: ->(_) { "CrossLint::App\n" })

    assert_empty covered
    assert_equal files, unmapped
  end

  def test_a_test_that_refers_to_no_subject_is_unmapped
    path = "test/cross_lint/adapters/report_test.rb"
    covered, unmapped = GateSubjects.covered([path], ALL, CONFIGURED, no_list, read: reading(path => "File.read\nDir.glob\n"))

    assert_empty covered
    assert_equal [path], unmapped
  end

  def test_a_plugin_with_no_source_expression_is_unmapped
    covered, unmapped = GateSubjects.covered(["plugins/debt/test/x_test.rb"], ALL, ["CrossLint*"], no_list)

    assert_empty covered
    assert_equal ["plugins/debt/test/x_test.rb"], unmapped
  end
end
