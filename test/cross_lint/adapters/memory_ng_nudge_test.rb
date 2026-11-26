# frozen_string_literal: true

require "test_helper"

class MemoryNgNudgeTest < Minitest::Test
  cover "CrossLint::Adapters::MemoryNgNudge*"

  include CrossLint::Testing::NgNudgeContract

  def ng_nudge_root = File.expand_path("/app")

  def ng_nudge_port(files) = CrossLint::Adapters::MemoryNgNudge.new({ng_nudge_root => files})

  def test_holds_no_project_unless_it_is_given_some
    port = CrossLint::Adapters::MemoryNgNudge.new

    assert_nil port.settings("/app")
    assert_empty port.extensions("/app")
  end
end
