# frozen_string_literal: true

require "test_helper"
require "rbconfig"
require "rubygems/package"
require "zlib"
require "digest"
require "stringio"
require_relative "../../tasks/bundled_works"

# tasks/bundled_works.rb: the license files of an npm package's release,
# which npm pack writes as a tarball, read without a registry once the
# tarball has the integrity the table lists. A script that Ruby runs
# stands in for npm.
class BundledWorksTest < Minitest::Test
  include TestHelper

  # What npm pack does for the package it is asked for: it writes the
  # tarball that ENV["TARBALL"] names, as the registry's tarball of
  # typescript 6.0.2, into the folder --pack-destination names, and prints
  # its name.
  PACK = <<~RUBY
    destination = ARGV.fetch(ARGV.index("--pack-destination") + 1)
    File.binwrite(File.join(destination, "typescript-6.0.2.tgz"), File.binread(ENV.fetch("TARBALL")))
    puts "typescript-6.0.2.tgz"
  RUBY

  def setup
    @folder = Dir.mktmpdir("bundled-works")
    @script = write(@folder, "pack.rb", PACK)
  end

  def teardown
    ENV.delete("TARBALL")
    FileUtils.remove_entry(@folder)
  end

  def test_reads_the_license_files_at_the_top_of_a_release_and_nothing_else
    integrity = pack("LICENSE.txt" => "Apache\n", "NOTICE" => "A notice\n", "ThirdPartyNoticeText.txt" => "Third party\n", "README.md" => "Readme\n",
      "package.json" => "{}", "lib/LICENSE" => "Nested\n", "bin/tsc" => "")

    texts = quietly { BundledWorks.npm_release(release(integrity), npm: command) }

    assert_equal({ "LICENSE.txt" => "Apache\n", "NOTICE" => "A notice\n", "ThirdPartyNoticeText.txt" => "Third party\n" }, texts)
  end

  def test_says_on_standard_error_what_it_fetches_and_for_how_long
    integrity = pack("LICENSE.txt" => "Apache\n")

    _, error = capture_io { BundledWorks.npm_release(release(integrity), npm: command) }

    assert_equal "npm_notices.rb: fetching typescript@6.0.2 from the npm registry, to read its license files, for at most 120 seconds\n", error
  end

  def test_refuses_a_release_with_no_license_file
    integrity = pack("NOTICE" => "A notice\n", "README.md" => "Readme\n")

    error = assert_raises(BundledWorks::Failure) { quietly { BundledWorks.npm_release(release(integrity), npm: command) } }

    assert_equal "typescript@6.0.2 has no license file", error.message
  end

  def test_refuses_a_tarball_whose_integrity_is_not_the_one_the_table_lists_and_names_the_work_the_version_and_both_values
    got = pack("LICENSE.txt" => "Apache\n")
    listed = "sha512-#{'A' * 86}=="

    error = assert_raises(BundledWorks::Failure) { quietly { BundledWorks.npm_release(release(listed), npm: command) } }

    assert_equal "TypeScript 6.0.2: the tarball that npm pack typescript@6.0.2 fetched has the integrity #{got}, and tasks/bundled_works.rb lists #{listed} for it. " \
      "If 6.0.2 is a new version, look at what its tarball ships, and then list its integrity in the table.", error.message
  end

  def test_refuses_a_tarball_of_a_version_whose_integrity_the_table_does_not_list
    got = pack("LICENSE.txt" => "Apache\n")

    error = assert_raises(BundledWorks::Failure) { quietly { BundledWorks.npm_release(release(nil), npm: command) } }

    assert_equal "TypeScript 6.0.2: the tarball that npm pack typescript@6.0.2 fetched has the integrity #{got}, and tasks/bundled_works.rb lists none for it. " \
      "If 6.0.2 is a new version, look at what its tarball ships, and then list its integrity in the table.", error.message
  end

  def test_checks_the_integrity_before_it_reads_a_file_of_the_tarball
    pack("README.md" => "No license file, which reading the tarball would refuse\n")

    error = assert_raises(BundledWorks::Failure) { quietly { BundledWorks.npm_release(release("sha512-#{'A' * 86}=="), npm: command) } }

    assert_match(/\ATypeScript 6\.0\.2: the tarball that npm pack typescript@6\.0\.2 fetched has the integrity /, error.message)
  end

  def test_refuses_a_run_of_npm_that_wrote_no_package
    error = assert_raises(BundledWorks::Failure) { quietly { BundledWorks.npm_release(release(nil), npm: [RbConfig.ruby, "-e", "exit"]) } }

    assert_equal "npm pack typescript@6.0.2 wrote no package", error.message
  end

  def test_says_what_npm_printed_when_it_fails
    error = assert_raises(BundledWorks::Failure) { BundledWorks.limited([RbConfig.ruby, "-e", "warn 'no network'; exit 1"], 30) }

    assert_match(/ failed:\nno network\n\z/, error.message)
  end

  # npm exits while a process it started still holds its output open, so
  # the readers are still reading when the run ends.
  def test_reads_until_the_output_ends_after_npm_exits
    late = [RbConfig.ruby, "-e", %(spawn(#{RbConfig.ruby.dump}, "-e", "sleep 0.3; print 'late'"))]

    _, error = capture_io { BundledWorks.limited(late, 30) }

    assert_equal "", error
  end

  def test_stops_a_run_of_npm_that_takes_longer_than_its_time_limit
    error = assert_raises(BundledWorks::Failure) { BundledWorks.limited([RbConfig.ruby, "-e", "sleep"], 0.5) }

    assert_match(/ -e sleep took more than 0\.5 seconds\z/, error.message)
  end

  def test_lists_the_integrity_of_each_version_of_typescript_that_the_build_has_read
    typescript = BundledWorks::WORKS.find { |work| work.name == "TypeScript" }

    assert_equal({ "6.0.2" => "sha512-bGdAIrZ0wiGDo5l8c++HWtbaNCWTS4UTv7RaTH/ThVIgjkveJt83m74bBHMJkuCbslY8ixgLBVZJIOiQlQTjfQ==" }, typescript.integrity)
  end

  def test_gives_the_release_of_a_found_work_the_integrity_the_table_lists_for_the_version_found
    work = BundledWorks::Work.new(name: "Work", license: "MIT", carriers: [], version: nil, source: "", release: "work", integrity: { "1.0.0" => "sha512-listed" })

    assert_equal BundledWorks::Release.new(work: "Work", package: "work", version: "1.0.0", integrity: "sha512-listed"),
      BundledWorks::Found.new(work:, version: "1.0.0", copyright: nil, places: []).release
    assert_nil BundledWorks::Found.new(work:, version: "1.0.1", copyright: nil, places: []).release.integrity
  end

  def test_gives_a_work_with_no_release_no_release_to_fetch
    work = BundledWorks::Work.new(name: "Work", license: "MIT", carriers: [], version: nil, source: "", release: nil, integrity: nil)

    assert_nil BundledWorks::Found.new(work:, version: nil, copyright: nil, places: []).release
  end

  private

  def command = [RbConfig.ruby, @script]

  def release(integrity) = BundledWorks::Release.new(work: "TypeScript", package: "typescript", version: "6.0.2", integrity:)

  # Writes the tarball of typescript 6.0.2 that the stand-in for npm pack
  # gives, with +files+ (path and text, under package/), and answers its
  # integrity, as the registry gives it.
  def pack(files)
    io = StringIO.new("".b)
    Zlib::GzipWriter.wrap(io) do |gzip|
      gzip.mtime = Time.at(0)
      Gem::Package::TarWriter.new(gzip) do |tar|
        files.each { |path, text| tar.add_file_simple("package/#{path}", 0o644, text.bytesize) { |file| file.write(text) } }
      end
    end
    ENV["TARBALL"] = write(@folder, "typescript.tgz", io.string)
    "sha512-#{Digest::SHA512.base64digest(io.string)}"
  end

  # The value of the block, with what it writes to standard error kept from the test's output.
  def quietly
    result = nil
    capture_io { result = yield }
    result
  end
end
