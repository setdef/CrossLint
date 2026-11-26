# frozen_string_literal: true

require "minitest/test_task"
require "rbconfig"
require "tmpdir"

# The tests, with the coverage test/test_helper.rb checks.
Minitest::TestTask.create(:test) do |task|
  task.test_globs = ["test/**/*_test.rb"]
  task.warning = true
end

# The same tests under RBS's runtime type checker, which raises at every
# call into CrossLint whose arguments, block, or result differ from
# sig/.
Minitest::TestTask.create("test:rbs") do |task|
  task.test_globs = ["test/**/*_test.rb"]
  task.warning = true
  task.test_prelude = [
    'ENV["RBS_TEST_TARGET"] = "CrossLint::*"',
    'ENV["RBS_TEST_OPT"] = "-r minitest -r pathname -I sig"',
    'ENV["RBS_TEST_RAISE"] = "true"',
    'ENV["RBS_TEST_LOGLEVEL"] = "error"',
    'require "rbs/test/setup"'
  ].join("; ")
end

namespace :rbs do
  desc "Validate the signatures in sig/"
  task :validate do
    sh "rbs", "-r", "minitest", "-r", "pathname", "-I", "sig", "validate"
  end

  desc "Check that every public part of CrossLint has a comment in sig/"
  task :comments do
    ruby "tasks/signature_comments.rb"
  end
end

desc "Run every Ruby example in the documentation, and check the results it shows"
task :doctest do
  ruby "-Ilib", "tasks/doctest.rb"
end

desc "Check the style of every Ruby file with Standard (.standard.yml)"
task :standard do
  sh "standardrb"
end

desc "Check lib/ against sig/ with Steep (Steepfile)"
task :steep do
  sh "steep", "check"
end

WINDOWS = RbConfig::CONFIG.fetch("host_os").match?(/mswin|mingw/)

desc "Run mutation testing on lib/ (.mutant.yml); mutant forks, so it doesn't run on Windows"
task :mutant do
  next puts("rake mutant: mutant doesn't run on Windows") if WINDOWS

  sh "bundle", "exec", "mutant", "run"
end

namespace :usage do
  desc "Lint crosslint.usage.kdl"
  task :lint do
    sh "usage", "lint", "crosslint.usage.kdl"
  end

  desc "Check that docs/reference/cli.md is what usage generates from crosslint.usage.kdl"
  task :reference do
    generated = IO.popen(%w[usage generate markdown --file crosslint.usage.kdl --out-file -], &:read)
    abort "rake usage:reference: usage generate markdown failed" unless $?.success?
    next if generated == File.read("docs/reference/cli.md")

    abort <<~MESSAGE
      rake usage:reference: docs/reference/cli.md isn't what crosslint.usage.kdl generates. Regenerate it with:
        usage generate markdown --file crosslint.usage.kdl --out-file docs/reference/cli.md
    MESSAGE
  end
end

desc "Check every file's copyright and license (REUSE.toml)"
task :reuse do
  sh "reuse", "lint"
end

desc "Run every check CI runs"
task check: [:standard, "rbs:validate", "rbs:comments", :steep, :test, "test:rbs", :doctest, :mutant, "usage:lint", "usage:reference", :reuse]

task default: :check

# The Fledge build: Fledge's bundle is in build/, so that the app
# doesn't carry Fledge, and the app leaves out the contributors' groups.
FLEDGE_ENV = {
  "BUNDLE_GEMFILE" => File.expand_path("build/Gemfile", __dir__),
  "BUNDLE_WITHOUT" => "development:test:check"
}.freeze

desc "Build the app for this computer with Fledge, into build/dist"
task :build do
  Bundler.with_unbundled_env do
    sh FLEDGE_ENV, "bundle", "install", chdir: "build"
    sh FLEDGE_ENV, "bundle", "exec", "fledge", "build", "..", chdir: "build"
  end
end

desc "Run the built app with nothing on PATH, and check its --version and --help"
task "build:check" do
  require_relative "lib/cross_lint"
  app = Dir["build/dist/*/crosslint{,.exe}"].first || abort("rake build:check: no app in build/dist; run rake build")
  spec = CrossLint::UsageSpec.load
  expected = {"--version" => "#{spec.bin} #{spec.version}\n", "--help" => CrossLint::Help.new(spec).render}
  Dir.mktmpdir do |empty|
    Bundler.with_unbundled_env do
      expected.each do |flag, output|
        actual = IO.popen({"PATH" => empty}, [File.expand_path(app), flag], err: %i[child out], &:read)
        abort "rake build:check: #{app} #{flag} exited with #{$?.exitstatus}:\n#{actual}" unless $?.success?
        abort "rake build:check: #{app} #{flag} printed:\n#{actual}" unless actual == output

        puts "#{app} #{flag}: matches the spec"
      end
    end
  end
end
