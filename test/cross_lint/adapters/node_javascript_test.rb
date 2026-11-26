# frozen_string_literal: true

require "test_helper"
require "rbconfig"

# Node is the one mise.toml pins, which the tests run on.
class NodeJavaScriptTest < Minitest::Test
  cover "CrossLint::Adapters::NodeJavaScript*"

  include CrossLint::Testing::JavaScriptContract

  JavaScriptError = CrossLint::Core::JavaScriptError

  FAKE_GLOB = <<~JS
    const path = require('path');
    exports.glob = async (pattern, options) => {
      if (pattern === '**/*.a.ts') return ['app/x.a.ts'];
      if (pattern === 'echo') return [path.basename(options.cwd), String(options.posix)];
      if (pattern === 'fails') throw new Error('glob stopped');
      return [];
    };
  JS

  def setup
    @root = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def glob_root = @root

  # The project has a fake glob in its node_modules, which answers as
  # glob_port says, unless it is not installed.
  def glob_port(installed)
    write(@root, "node_modules/glob/index.js", FAKE_GLOB) if installed
    javascript_port
  end

  def javascript_port = CrossLint::Adapters::NodeJavaScript.new

  def test_finds_a_glob_in_the_first_folder_that_has_one_and_looks_in_a_folder_of_the_project
    write(@root, "tool/node_modules/glob/index.js", FAKE_GLOB)
    found = javascript_port.glob(@root, "src", ["echo"], ["nothing", "tool", ""])

    assert_equal({"echo" => ["src", "true"]}, found)
  end

  def test_finds_a_glob_for_a_root_given_relative_to_the_current_folder
    glob_port(true)
    found = Dir.chdir(File.dirname(@root)) { javascript_port.glob(File.basename(@root), "src", ["echo"], [""]) }

    assert_equal({"echo" => ["src", "true"]}, found)
  end

  def test_says_what_glob_stopped_with
    glob_port(true)
    error = assert_raises(JavaScriptError) { javascript_port.glob(@root, "src", ["fails"], [""]) }

    assert_equal "glob stopped", error.message
  end

  def test_says_what_node_wrote_when_the_glob_package_cannot_be_loaded
    write(@root, "node_modules/glob/index.js", "this is not javascript")
    error = assert_raises(JavaScriptError) { javascript_port.glob(@root, "src", ["a"], [""]) }

    assert_match(/\Anode exited with status 1, and wrote:\n.*SyntaxError/m, error.message)
  end

  def test_gives_the_message_node_gives_for_an_expression_it_does_not_accept
    error = assert_raises(CrossLint::Core::InvalidExpression) { javascript_port.matches("(", ["a"]) }

    assert_match(/\AInvalid regular expression: \/\(\/.*: Unterminated group\z/, error.message)
  end

  def test_gives_the_message_node_gives_for_a_quantifier_on_an_anchor_though_no_text_is_tested
    error = assert_raises(CrossLint::Core::InvalidExpression) { javascript_port.matches("^*", []) }

    assert_match(/\AInvalid regular expression: \/\^\*\/.*: Nothing to repeat\z/, error.message)
  end

  def test_does_not_call_a_failure_of_node_an_invalid_expression
    error = assert_raises(JavaScriptError) { CrossLint::Adapters::NodeJavaScript.new(command: "crosslint-no-such-node").matches("a", []) }

    refute_kind_of CrossLint::Core::InvalidExpression, error
  end

  def test_tests_a_text_for_each_of_many_texts_without_stopping_on_a_full_pipe
    texts = Array.new(50_000) { |index| "line #{index} é" }

    assert_equal texts.map { |text| text.end_with?("7 é") }, javascript_port.matches("7 é$", texts)
  end

  def test_tests_each_text_afresh_so_that_one_does_not_change_the_next
    assert_equal [true, true, true], javascript_port.matches("a", %w[a a a])
  end

  def test_says_to_install_node_when_the_command_is_not_there
    error = assert_raises(JavaScriptError) { CrossLint::Adapters::NodeJavaScript.new(command: "crosslint-no-such-node").matches("a", ["a"]) }

    assert_match(/\Acouldn't run crosslint-no-such-node, which CrossLint runs to ask about regular expressions and files, so install Node: \S/, error.message)
  end

  def test_says_what_the_program_wrote_when_it_exits_with_a_failure
    port = CrossLint::Adapters::NodeJavaScript.new(script: "process.stderr.write('nope'); process.exit(3)")
    error = assert_raises(JavaScriptError) { port.matches("a", ["a"]) }

    assert_equal "node exited with status 3, and wrote:\nnope", error.message
  end

  def test_says_what_the_program_answered_when_it_ends_without_reading_its_input
    port = CrossLint::Adapters::NodeJavaScript.new(script: "process.exit(0)")
    error = assert_raises(JavaScriptError) { port.matches("a", Array.new(50_000) { |index| "line #{index} é" }) }

    assert_equal %(node answered with something that isn't JSON: ""), error.message
  end

  def test_says_what_the_program_answered_when_it_is_not_json
    port = CrossLint::Adapters::NodeJavaScript.new(script: "process.stdout.write('not json')")
    error = assert_raises(JavaScriptError) { port.matches("a", ["a"]) }

    assert_equal %(node answered with something that isn't JSON: "not json"), error.message
  end

  def test_says_the_program_did_not_answer_and_ends_it_after_the_limit
    port = CrossLint::Adapters::NodeJavaScript.new(script: "setTimeout(() => {}, 60000)", limit: 0.5)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(JavaScriptError) { port.matches("a", ["a"]) }

    assert_equal "node didn't answer within 0.5s", error.message
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 30
  end

  def test_ends_an_expression_that_never_finishes_matching
    port = CrossLint::Adapters::NodeJavaScript.new(limit: 1)
    error = assert_raises(JavaScriptError) { port.matches("^(a+)+$", ["#{"a" * 60}b"]) }

    assert_equal "node didn't answer within 1s", error.message
  end

  def test_gives_the_program_the_time_limit_it_defaults_to
    assert_equal [10, 10, 3], [CrossLint::Adapters::NodeJavaScript::LIMIT, CrossLint::Adapters::NodeJavaScript.new.limit, CrossLint::Adapters::NodeJavaScript.new(limit: 3).limit]
  end

  def test_reads_what_the_program_wrote_as_utf_8_and_replaces_a_byte_that_is_not
    script = "process.stderr.write(Buffer.from([0x61, 0xc3, 0xa9, 0xff, 0x62])); process.exit(3)"
    error = assert_raises(JavaScriptError) { with_default_external(Encoding::ISO_8859_1) { CrossLint::Adapters::NodeJavaScript.new(script:).matches("a", ["a"]) } }

    assert_equal "node exited with status 3, and wrote:\naé�b", error.message
  end

  # Runs the block with another default external encoding, which is what
  # a pipe is read in.
  def with_default_external(encoding)
    verbose = $VERBOSE
    before = Encoding.default_external
    $VERBOSE = nil
    Encoding.default_external = encoding
    yield
  ensure
    Encoding.default_external = before
    $VERBOSE = verbose
  end
end
