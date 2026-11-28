# frozen_string_literal: true

require "test_helper"
require "rbconfig"
require "rubygems/package"
require "zlib"
require_relative "../../tasks/bundled_works"

# tasks/bundled_works.rb: the license files of an npm package's release,
# which npm pack writes as a tarball, read without a registry. A script
# that Ruby runs stands in for npm.
class BundledWorksTest < Minitest::Test
  include TestHelper

  # What npm pack does for the package it is asked for: it writes a
  # tarball of +files+ (path and text, under package/) into the folder
  # --pack-destination names, and prints its name.
  PACK = <<~'RUBY'
    require "rubygems/package"
    require "zlib"
    require "json"
    files = JSON.parse(File.binread(ENV.fetch("FILES")))
    destination = ARGV.fetch(ARGV.index("--pack-destination") + 1)
    File.open(File.join(destination, "typescript-6.0.2.tgz"), "wb") do |file|
      Zlib::GzipWriter.wrap(file) do |gzip|
        Gem::Package::TarWriter.new(gzip) do |tar|
          files.each { |path, text| tar.add_file_simple("package/#{path}", 0o644, text.bytesize) { |io| io.write(text) } }
        end
      end
    end
    puts "typescript-6.0.2.tgz"
  RUBY

  def setup
    @folder = Dir.mktmpdir("bundled-works")
    @script = write(@folder, "pack.rb", PACK)
  end

  def teardown
    ENV.delete("FILES")
    FileUtils.remove_entry(@folder)
  end

  def test_reads_the_license_files_at_the_top_of_a_release_and_nothing_else
    pack("LICENSE.txt" => "Apache\n", "NOTICE" => "A notice\n", "ThirdPartyNoticeText.txt" => "Third party\n", "README.md" => "Readme\n",
      "package.json" => "{}", "lib/LICENSE" => "Nested\n", "bin/tsc" => "")

    texts = quietly { BundledWorks.npm_release("typescript", "6.0.2", npm: command) }

    assert_equal({"LICENSE.txt" => "Apache\n", "NOTICE" => "A notice\n", "ThirdPartyNoticeText.txt" => "Third party\n"}, texts)
  end

  def test_says_on_standard_error_what_it_fetches_and_for_how_long
    pack("LICENSE.txt" => "Apache\n")

    _, error = capture_io { BundledWorks.npm_release("typescript", "6.0.2", npm: command) }

    assert_equal "npm_notices.rb: fetching typescript@6.0.2 from the npm registry, to read its license files, for at most 120 seconds\n", error
  end

  def test_refuses_a_release_with_no_license_file
    pack("NOTICE" => "A notice\n", "README.md" => "Readme\n")

    error = assert_raises(BundledWorks::Failure) { quietly { BundledWorks.npm_release("typescript", "6.0.2", npm: command) } }

    assert_equal "typescript@6.0.2 has no license file", error.message
  end

  def test_refuses_a_run_of_npm_that_wrote_no_package
    error = assert_raises(BundledWorks::Failure) { quietly { BundledWorks.npm_release("typescript", "6.0.2", npm: [RbConfig.ruby, "-e", "exit"]) } }

    assert_equal "npm pack typescript@6.0.2 wrote no package", error.message
  end

  def test_says_what_npm_printed_when_it_fails
    error = assert_raises(BundledWorks::Failure) { BundledWorks.limited([RbConfig.ruby, "-e", "warn 'no network'; exit 1"], 30) }

    assert_match(/ failed:\nno network\n\z/, error.message)
  end

  def test_stops_a_run_of_npm_that_takes_longer_than_its_time_limit
    error = assert_raises(BundledWorks::Failure) { BundledWorks.limited([RbConfig.ruby, "-e", "sleep"], 0.5) }

    assert_match(/ -e sleep took more than 0\.5 seconds\z/, error.message)
  end

  private

  def command = [RbConfig.ruby, @script]

  def pack(files)
    ENV["FILES"] = write(@folder, "files", JSON.generate(files))
  end

  # The value of the block, with what it writes to standard error kept from the test's output.
  def quietly
    result = nil
    capture_io { result = yield }
    result
  end
end
