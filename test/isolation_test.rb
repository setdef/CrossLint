# frozen_string_literal: true

require "test_helper"

# What test/test_helper.rb does so that no test reaches
# the user's home folder, cache, or Git settings.
class IsolationTest < Minitest::Test
  def test_points_every_folder_a_program_would_use_in_the_users_home_at_a_folder_that_goes_with_the_run
    assert_equal [SANDBOX_HOME] * 3, [*ENV.values_at("HOME", "USERPROFILE"), Dir.home]
    assert_equal [CACHE] * 2, [ENV["XDG_CACHE_HOME"], ENV["LOCALAPPDATA"]]
    assert_equal [SANDBOX] * 2, [File.dirname(SANDBOX_HOME), File.dirname(CACHE)]
  end

  def test_gives_git_its_settings_in_one_file_and_reads_no_other_configuration
    listed, error, status = Open3.capture3("git", "config", "--list", "--show-origin", chdir: SANDBOX)
    # "command line:" marks a setting given with git -c, which is no file.
    origins = listed.lines.map { |line| line.split("\t", 2).first }.uniq - ["command line:"]

    assert_predicate status, :success?, error
    assert_equal ["file:#{ENV.fetch('GIT_CONFIG_GLOBAL')}"], origins
    assert_equal File.join(SANDBOX, "gitconfig"), ENV.fetch("GIT_CONFIG_GLOBAL")
    assert_includes listed, "user.name=Test"
  end
end
