# frozen_string_literal: true

require "test_helper"

# What ReplaceFile can't show through the files that use it: the error a
# write ends with when the system denies the rename and then the deletion of
# the file it wrote beside.
class ReplaceFileTest < Minitest::Test
  cover "CrossLint::Adapters::ReplaceFile*"

  # Denies each File.rename in this thread while :crosslint_replace_rename_denied
  # is set, as Windows does over a file another program has open.
  module DeniedRenames
    def rename(from, to)
      raise Errno::EACCES, "rename" if Thread.current[:crosslint_replace_rename_denied]

      super
    end
  end
  File.singleton_class.prepend(DeniedRenames)

  # Denies each File.delete and File.unlink in this thread while
  # :crosslint_replace_delete_denied is set.
  module DeniedDeletes
    def delete(*files)
      raise Errno::EACCES, "delete" if Thread.current[:crosslint_replace_delete_denied]

      super
    end

    def unlink(*files)
      raise Errno::EACCES, "delete" if Thread.current[:crosslint_replace_delete_denied]

      super
    end
  end
  File.singleton_class.prepend(DeniedDeletes)

  def setup
    @root = Dir.mktmpdir("crosslint")
    @file = File.join(@root, "a.txt")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_replaces_the_file_and_leaves_nothing_beside_it
    File.write(@file, "old")
    CrossLint::Adapters::ReplaceFile.call(@file, "new")

    assert_equal ["new", ["a.txt"]], [File.read(@file), Dir.children(@root)]
  end

  def test_ends_with_the_error_of_the_rename_when_the_system_denies_the_deletion_of_the_file_it_wrote
    File.write(@file, "old")
    error = denying(:rename, :delete) { assert_raises(Errno::EACCES) { CrossLint::Adapters::ReplaceFile.call(@file, "new") } }

    assert_equal ["Permission denied - rename", "old"], [error.message, File.read(@file)]
  end

  private def denying(*actions)
    actions.each { |action| Thread.current[:"crosslint_replace_#{action}_denied"] = true }
    yield
  ensure
    actions.each { |action| Thread.current[:"crosslint_replace_#{action}_denied"] = nil }
  end
end
