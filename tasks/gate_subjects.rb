# frozen_string_literal: true

# Which mutation subjects the gate (rake gate:mutant) tests for a change.
# Mutant's --since selects the subjects whose source lines a change
# touches, so a change to a test alone selects none, and a deleted
# assertion would pass. A changed test also selects the subjects it covers:
# those named by its path (test/cross_lint/core/load_project_test.rb covers
# CrossLint::Core::LoadProject*), and those whose classes its text refers
# to, which is how a contract test that runs across several adapters covers
# each of them. A test under plugins/NAME/test/ covers the subjects
# .mutant.yml lists for that plugin's Ruby.
module GateSubjects
  module_function

  # The tests of tasks/ and .github/, whose code mutant doesn't mutate,
  # are no test of a subject, and cover none.
  def test_file?(path)
    return false if path.start_with?("test/tasks/", "test/github/")

    path.start_with?("test/") || path.match?(%r{\Aplugins/[^/]+/test/})
  end

  # The name a test file's path gives to the classes it covers, or nil for
  # a file that isn't named like a test of one. Case doesn't count, and
  # nor do underscores, so cli_test.rb covers CrossLint::CLI, and kdl
  # covers KDL: the prefix is lowercase, to match against lowercased names.
  def class_prefix(path)
    stem = path[%r{\Atest/(.+)_test\.rb\z}, 1]
    stem&.split("/")&.map { |part| part.delete("_").downcase }&.join("::")
  end

  def plugin_name(path)
    path[%r{\Aplugins/([^/]+)/test/}, 1]
  end

  # The subject expressions .mutant.yml lists for one plugin's Ruby.
  def plugin_expressions(configured, name)
    configured.grep(%r{\Asource:plugins/\*/}).map { |expression| expression.sub("plugins/*/", "plugins/#{name}/") }
  end

  # The tests that cut across the code, so a change to one runs every subject.
  CROSS_CUTTING = %w[
    test/test_helper.rb
    test/isolation_test.rb
    test/cross_lint/architecture_test.rb
    test/cross_lint/exe_test.rb
    test/cross_lint/plugins_test.rb
  ].freeze

  # Namespaces that name no subject on their own.
  NAMESPACES = %w[CrossLint Core Adapters Testing].freeze

  CONSTANT = /\b[A-Z][A-Za-z0-9]*(?:::[A-Z][A-Za-z0-9]*)*/

  # The constants a test file's text refers to, each as the chain it is
  # written with and every leading part of that chain except a bare
  # namespace: Adapters::ProcessHelpers::TREE gives itself and
  # Adapters::ProcessHelpers, so the test covers ProcessHelpers.
  def references(source)
    names = source.scan(CONSTANT).flat_map do |chain|
      parts = chain.split("::")
      (1..parts.size).map { |size| parts.first(size).join("::") }
    end
    names.uniq.reject { |name| (name.split("::") - NAMESPACES).empty? }
  end

  # The class a subject's name starts with: CrossLint::CLI#run is CrossLint::CLI.
  def subject_class(name)
    name[/\A[^#.]+/]
  end

  # The subjects a test file's references name. A reference names a subject
  # when it is a run of parts of the subject's class: Condition::CompanionExists
  # names CrossLint::Core::Condition::CompanionExists#applies.
  def named(references, all)
    all.select do |name|
      wrapped = "::#{subject_class(name)}::"
      references.any? { |reference| wrapped.include?("::#{reference}::") }
    end
  end

  # The tests of a class mutant doesn't run (.mutant.yml ignores it), which
  # cover no subject and are no reason to run every one.
  NO_SUBJECT = %w[
    test/cross_lint/adapters/job_object_test.rb
  ].freeze

  # The subjects the changed test files cover, and the test files that
  # cover none. all is every subject's name; configured is .mutant.yml's
  # list of subject expressions; list is called with expressions, and
  # returns the names of the subjects they select; read is called with a
  # test file's path and returns its text. A test file covers the subjects
  # whose classes it refers to, so a new test file maps with no table to
  # maintain. A test of a class mutant doesn't run selects no subject, and
  # a line on out says so. A test file that cuts across the code, or that
  # refers to no class of a subject, is unmapped, so every subject runs.
  def covered(files, all, configured, list, read: ->(path) { File.read(path) }, out: $stdout)
    subjects = []
    unmapped = []
    files.select { |file| test_file?(file) }.each do |file|
      if NO_SUBJECT.include?(file)
        out.puts "rake gate:mutant: #{file} tests only code that mutant doesn't run, so it selects no subject"
      elsif CROSS_CUTTING.include?(file)
        unmapped << file
      elsif (plugin = plugin_name(file))
        expressions = plugin_expressions(configured, plugin)
        found = expressions.empty? ? [] : list.call(expressions)
        found.empty? ? unmapped << file : subjects.concat(found)
      else
        found = named(references(read.call(file)), all)
        prefix = class_prefix(file)
        found += all.select { |name| name.downcase.start_with?(prefix) } if prefix
        found.empty? ? unmapped << file : subjects.concat(found)
      end
    end
    [subjects.uniq, unmapped]
  end
end
