# frozen_string_literal: true

# Which mutation subjects the gate (rake gate:mutant) tests for a change.
# Mutant's --since selects the subjects whose source lines a change
# touches, so a change to a test alone selects none, and a deleted
# assertion would pass. A changed test also selects the subjects it covers,
# found by the path convention: test/cross_lint/core/load_project_test.rb
# covers CrossLint::Core::LoadProject*, and a test under plugins/NAME/test/
# covers the subjects .mutant.yml lists for that plugin's Ruby.
module GateSubjects
  module_function

  # The tests of tasks/ and .github/, whose code mutant doesn't mutate,
  # are no test of a subject, and cover none.
  def test_file?(path)
    return false if path.start_with?("test/tasks/", "test/github/")

    path.start_with?("test/") || path.match?(%r{\Aplugins/[^/]+/test/})
  end

  # The name a test file's path gives to the classes it covers, or nil for
  # a file that isn't named like a test of one.
  def class_prefix(path)
    stem = path[%r{\Atest/(.+)_test\.rb\z}, 1]
    stem&.split("/")&.map { |part| part.split("_").map(&:capitalize).join }&.join("::")
  end

  def plugin_name(path)
    path[%r{\Aplugins/([^/]+)/test/}, 1]
  end

  # The subject expressions .mutant.yml lists for one plugin's Ruby.
  def plugin_expressions(configured, name)
    configured.grep(%r{\Asource:plugins/\*/}).map { |expression| expression.sub("plugins/*/", "plugins/#{name}/") }
  end

  # The subjects the changed test files cover, and the test files that
  # cover none. all is every subject's name; configured is .mutant.yml's
  # list of subject expressions; list is called with expressions, and
  # returns the names of the subjects they select.
  def covered(files, all, configured, list)
    subjects = []
    unmapped = []
    files.select { |file| test_file?(file) }.each do |file|
      found =
        if (plugin = plugin_name(file))
          expressions = plugin_expressions(configured, plugin)
          expressions.empty? ? [] : list.call(expressions)
        elsif (prefix = class_prefix(file))
          all.select { |name| name.start_with?(prefix) }
        else
          []
        end
      found.empty? ? unmapped << file : subjects.concat(found)
    end
    [subjects.uniq, unmapped]
  end
end
