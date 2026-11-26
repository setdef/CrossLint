# frozen_string_literal: true

require "minitest/test_task"
require "rbconfig"

# The tests, with the coverage test/test_helper.rb checks.
Minitest::TestTask.create(:test) do |task|
  task.test_globs = ["test/**/*_test.rb"]
  task.warning = true
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
task check: [:test, :mutant, "usage:lint", "usage:reference", :reuse]

task default: :check
