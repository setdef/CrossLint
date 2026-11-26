# frozen_string_literal: true

require "test_helper"

class MemoryProjectFilesTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryProjectFiles*"

  include CrossLint::Testing::ProjectFilesContract

  def project_files_port(listed:, ignored: [])
    contents = (listed + ignored).to_h { |path| [path, "#{path}\n"] }
    CrossLint::Adapters::MemoryProjectFiles.new({project_root => listed}, ignored: {project_root => ignored}, contents: {project_root => contents})
  end

  def project_root = "/memory/app"

  def outside_root = "/memory/elsewhere"

  def test_holds_no_project_unless_it_is_given_some
    port = CrossLint::Adapters::MemoryProjectFiles.new

    assert_raises(CrossLint::Core::Mistake) { port.files(project_root) }
    refute port.exist?(project_root, "lib")
    assert_raises(Errno::ENOENT) { port.read(project_root, "lib/a.rb") }
  end

  def test_finds_a_listed_file_with_no_ignored_files_given
    assert CrossLint::Adapters::MemoryProjectFiles.new({project_root => ["a.rb"]}).exist?(project_root, "a.rb")
  end
end
