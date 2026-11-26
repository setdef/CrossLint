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
    'ENV["RBS_TEST_OPT"] = "-r fileutils -r json -r minitest -r open3 -r pathname -I sig"',
    'ENV["RBS_TEST_RAISE"] = "true"',
    'ENV["RBS_TEST_LOGLEVEL"] = "error"',
    'require "rbs/test/setup"'
  ].join("; ")
end

namespace :rbs do
  desc "Validate the signatures in sig/"
  task :validate do
    sh "rbs", "-r", "fileutils", "-r", "json", "-r", "minitest", "-r", "open3", "-r", "pathname", "-I", "sig", "validate"
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

desc "Check that every file under lib/ has its signature under sig/, with CrossLint itself (.config/crosslint/config.kdl)"
task :crosslint do
  ruby "exe/crosslint", "check"
end

desc "Run every check CI runs"
task check: [:standard, "rbs:validate", "rbs:comments", :steep, :test, "test:rbs", :doctest, :mutant, :crosslint, "usage:lint",
  "usage:reference", :reuse]

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

desc "Run the built app with nothing on PATH, and check its --version and --help, and its rules in Ruby and helpers"
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
  Rake::Task["build:check:plugins"].invoke(app)
end

# A project whose rules in Ruby run on the app's Ruby, the way an app
# loads gems: one plugin's rule asks a helper that runs on sh, one's
# requires a gem the app wasn't built with, and one's requires
# bundler/inline. PATH holds only the folders of Git and sh.
task "build:check:plugins", [:app] do |_, arguments|
  app = File.expand_path(arguments.fetch(:app))
  rule = ->(name, body) { %(class #{name} < CrossLint::Rule\n  def check(artifact)\n    #{body}\n  end\nend\n) }
  plugin = ->(rule_name, extra = "") { %(artifact "doc" {\n  files "{path}.md"\n}\nrule "#{rule_name}" ruby="rule.rb"\n#{extra}policy "p" {\n  applies-to "doc"\n  rule "#{rule_name}"\n}\n) }
  files = {
    ".config/crosslint/config.kdl" => %w[asks gems inline].map { |name| %(plugin ".config/crosslint/#{name}"\n) }.join,
    ".config/crosslint/asks/plugin.kdl" => plugin.call("asks", %(helper "answers" command="sh" file="answers.sh"\n)),
    ".config/crosslint/asks/rule.rb" => rule.call("Asks", %([violation(artifact, "answered \#{helper("answers").call("hi")}")])),
    ".config/crosslint/asks/answers.sh" => %(while read -r line; do echo "$line"; done\n),
    ".config/crosslint/gems/plugin.kdl" => plugin.call("uses-gem"),
    ".config/crosslint/gems/rule.rb" => %(require "rainbow"\n) + rule.call("UsesGem", "[]"),
    ".config/crosslint/inline/plugin.kdl" => plugin.call("uses-inline"),
    ".config/crosslint/inline/rule.rb" => %(require "bundler/inline"\n) + rule.call("UsesInline", "[]"),
    "a.md" => ""
  }
  finder = CrossLint::Adapters::ProcessHelpers.new(err: $stderr, debug: false)
  path = %w[git sh].map { |command| File.dirname(finder.find(command) || abort("rake build:check: no #{command} on the PATH")) }.uniq
  expected = [
    "a.md: answered hi (asks/p)",
    "crosslint: fault in plugin gems: rule uses-gem requires rainbow, which is neither in Ruby's standard library nor in the plugin's folder, " \
      "and CrossLint can load no gem it wasn't built with",
    "crosslint: fault in plugin inline: rule uses-inline requires bundler/inline, which CrossLint doesn't offer, since it would install gems into CrossLint's folder"
  ]
  Dir.mktmpdir do |project|
    files.each do |file, text|
      FileUtils.mkdir_p(File.dirname(File.join(project, file)))
      File.binwrite(File.join(project, file), text)
    end
    Bundler.with_unbundled_env do
      system("git", "init", "-q", chdir: project) || abort("rake build:check: git init failed")
      actual = IO.popen({"PATH" => path.join(File::PATH_SEPARATOR)}, [app, "check", "-C", project], err: %i[child out], &:read)
      lines = actual.lines(chomp: true)
      abort "rake build:check: #{app} check exited with #{$?.exitstatus}, not 2:\n#{actual}" unless $?.exitstatus == 2
      abort "rake build:check: #{app} check printed:\n#{actual}" unless (expected - lines).empty?

      puts "#{app} check: runs a rule in Ruby that asks a helper, and refuses a gem and bundler/inline"
    end
  end
end
