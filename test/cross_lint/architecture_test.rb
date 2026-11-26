# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# What docs/design/architecture.md requires of how the code divides.
class ArchitectureTest < Minitest::Test
  def test_the_core_loads_with_nothing_outside_rubys_standard_library
    script = 'require "cross_lint/core"; puts $LOADED_FEATURES'
    out, err, status = Open3.capture3({"RUBYOPT" => nil}, RbConfig.ruby, "--disable-gems", "-I", File.join(ROOT, "lib"), "-e", script)

    assert_predicate status, :success?, err
    core = File.join(ROOT, "lib", "cross_lint", "core")
    standard = [RbConfig::CONFIG.fetch("rubylibdir"), RbConfig::CONFIG.fetch("archdir")]
    outside = out.lines(chomp: true).select { |feature| File.absolute_path?(feature) }.reject do |feature|
      feature.start_with?(*standard) || feature == "#{core}.rb" || feature.start_with?("#{core}/")
    end

    assert_empty outside
  end

  def test_every_file_under_lib_has_a_signature_at_the_matching_path_under_sig
    missing = Dir.glob("lib/**/*.rb", base: ROOT).map { |file| file.sub(%r{\Alib/(.*)\.rb\z}, 'sig/\1.rbs') }
      .reject { |signature| File.file?(File.join(ROOT, signature)) }

    assert_empty missing
  end
end
