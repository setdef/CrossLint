# frozen_string_literal: true

require "test_helper"

class FileNgNudgeTest < Minitest::Test
  cover "CrossLint::Adapters::FileNgNudge*"

  include CrossLint::Testing::NgNudgeContract

  def setup
    @root = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def ng_nudge_root = @root

  def ng_nudge_port(files)
    files.each { |path, text| write(@root, path, text) }
    CrossLint::Adapters::FileNgNudge.new
  end

  def test_refuses_an_rc_json_that_is_not_utf_8
    write(@root, ".config/ng-nudge/rc.json", "{\"srcDir\": \"\xFF\"}")
    mistake = assert_raises(CrossLint::Core::Mistake) { CrossLint::Adapters::FileNgNudge.new.settings(@root) }

    assert_equal [".config/ng-nudge/rc.json", nil, "isn't valid UTF-8"], [mistake.file, mistake.line, mistake.message]
  end

  def test_lists_no_folder_named_like_a_file_ng_nudge_loads
    FileUtils.mkdir_p(File.join(@root, ".config/ng-nudge/rules/a.rule.js"))

    assert_empty CrossLint::Adapters::FileNgNudge.new.extensions(@root)
  end
end
