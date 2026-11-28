# frozen_string_literal: true

require "minitest/test_task"
require "tmpdir"

# CrossLint's tests, and each built-in plugin's in its own folder, so a
# plugin can move to a repository of its own with its tests.
TESTS = ["test/**/*_test.rb", "plugins/*/test/**/*_test.rb"].freeze

# The tests, with the coverage test/test_helper.rb checks.
Minitest::TestTask.create(:test) do |task|
  task.test_globs = TESTS
  task.warning = true
end

# The packages each built-in plugin needs when it runs, which its
# package-lock.json locks, installed with npm ci and no dev dependencies.
# The app carries them: Fledge copies the plugin's node_modules with the
# rest of the project, and leaves out only a folder a CACHEDIR.TAG marks.
# The build (rake build) runs this task before it builds; setup runs it
# with the fixtures. A plugin installed
# from the same lockfile is left as it is.
desc "Install the packages each built-in plugin runs with, with npm ci"
task :packages do
  Dir.glob("plugins/*/package-lock.json").each do |lock|
    install_packages(lock, "--omit=dev")
  end
end

# The packages a built-in plugin's test fixture locks in its
# package-lock.json, installed with npm ci, after each plugin's own.
# Setup does this, once, after installing the tools: no test task depends
# on it, and a test whose fixture has no packages fails saying to run it.
# A fixture installed from the same lockfile is left as it is.
# CACHEDIR.TAG marks a fixture's node_modules as a folder a tool makes,
# which the Fledge build leaves out of the app.
desc "Install the packages each built-in plugin and its test fixtures lock, with npm ci"
task fixtures: :packages do
  Dir.glob("plugins/*/test/**/package-lock.json").reject { |lock| lock.include?("/node_modules/") }.each do |lock|
    install_packages(lock, tag: true)
  end
end

# Installs the packages LOCK locks into the node_modules beside it, with
# npm ci and OPTIONS, unless that lockfile installed them already; with
# TAG, marks the folder as one the app leaves out.
def install_packages(lock, *options, tag: false)
  modules = File.join(File.dirname(lock), "node_modules")
  installed = File.join(modules, ".crosslint-package-lock.json")
  return if File.file?(installed) && File.binread(installed) == File.binread(lock)

  sh "npm", "ci", "--no-audit", "--no-fund", *options, chdir: File.dirname(lock)
  File.binwrite(File.join(modules, "CACHEDIR.TAG"), "Signature: 8a477f597d28d172789f06886806bc55\n# rake fixtures makes this folder again with npm ci.\n") if tag
  File.binwrite(installed, File.binread(lock))
end

# The same tests under RBS's runtime type checker, which raises at every
# call into CrossLint whose arguments, block, or result differ from
# sig/.
Minitest::TestTask.create("test:rbs") do |task|
  task.test_globs = TESTS
  task.warning = true
  task.test_prelude = [
    'ENV["RBS_TEST_TARGET"] = "CrossLint::*"',
    'ENV["RBS_TEST_OPT"] = "-r digest -r fileutils -r json -r minitest -r open3 -r pathname -r securerandom -I sig"',
    'ENV["RBS_TEST_RAISE"] = "true"',
    'ENV["RBS_TEST_LOGLEVEL"] = "error"',
    'require "rbs/test/setup"'
  ].join("; ")
end

namespace :rbs do
  desc "Validate the signatures in sig/"
  task :validate do
    sh "rbs", "-r", "digest", "-r", "fileutils", "-r", "json", "-r", "minitest", "-r", "open3", "-r", "pathname", "-r", "securerandom", "-I", "sig", "validate"
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

desc "Check CrossLint with CrossLint itself (.config/crosslint/config.kdl): each file under lib/ has its signature under sig/, and each relative Markdown link resolves"
task :crosslint do
  ruby "exe/crosslint", "check"
end

# Every check CI's Linux job runs, cheapest first, which is also what to
# run before a push. The tests run a second time under RBS's runtime type
# checker (test:rbs), since a call that breaks sig/ is otherwise found
# only after the push.
desc "Run every check CI's Linux job runs"
task check: ["usage:lint", "usage:reference", :doctest, :crosslint, "rbs:comments", "rbs:validate", :standard, :reuse, :steep, :test, "test:rbs"]

desc "Run every check, before a push"
task gate: :check

task default: :check

# The Fledge build: Fledge's bundle is in build/, so that the app
# doesn't carry Fledge, and the app leaves out the contributors' groups.
FLEDGE_ENV = {
  "BUNDLE_GEMFILE" => File.expand_path("build/Gemfile", __dir__),
  "BUNDLE_WITHOUT" => "development:test:check"
}.freeze

# The app carries the packages rake packages installs, so the build needs
# them, and lists each in the notices (tasks/npm_notices.rb), which Fledge
# writes for the runtime alone. The task packs each archive again with
# the notices, and fails when an archive's notices or SBOM lack a package
# it carries.
desc "Build the app for this computer with Fledge, into build/dist"
task build: :packages do
  # build/Gemfile.lock names the Bundler that locked it, and a Bundler of
  # another version rewrites that name in the lock. Bundler switches to
  # the locked version when it finds that version among the gems it can
  # see. Where BUNDLE_PATH holds the bundle, the project's bundle has
  # installed the locked Bundler there, and with_unbundled_env drops the
  # variables that point to it, so a Bundler that comes with a newer Ruby
  # (RubyInstaller's, on Windows) would not find it. GEM_PATH points the
  # build's Bundler to the same gems that this rake task sees.
  env = FLEDGE_ENV.merge("GEM_PATH" => (Gem.path + [Gem.default_dir]).uniq.join(File::PATH_SEPARATOR))
  Bundler.with_unbundled_env do
    sh env, "bundle", "install", chdir: "build"
    sh env, "bundle", "exec", "fledge", "build", "..", chdir: "build"
    sh env, "bundle", "exec", "ruby", "../tasks/npm_notices.rb", "dist", chdir: "build"
  end
end

desc "Run the built app with nothing on PATH, and check its --version and --help, its notices and SBOM, its rules in Ruby and helpers, " \
  "the environment of a helper, its built-in plugins and their commands, and a shared plugin"
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
  Rake::Task["build:check:notices"].invoke(app)
  Rake::Task["build:check:plugins"].invoke(app)
  Rake::Task["build:check:environment"].invoke(app)
  Rake::Task["build:check:debt"].invoke(app)
  Rake::Task["build:check:angular"].invoke(app)
  Rake::Task["build:check:shared"].invoke(app)
end

# The built app's notices and SBOM list each npm package the app carries,
# with its version and license, which rake build puts there for each
# archive and checks in the archive.
task "build:check:notices", [:app] do |_, arguments|
  require_relative "tasks/npm_notices"
  folder = File.dirname(File.expand_path(arguments.fetch(:app)))
  carried = NpmNotices.installed(folder)
  abort "rake build:check: #{folder} carries no npm package, and the Angular plugin needs ts-morph" if carried.empty?

  problems = NpmNotices.problems(folder)
  abort "rake build:check: #{folder}:\n#{problems.join("\n")}" unless problems.empty?

  puts "#{folder}: lists the #{carried.size} npm packages it carries in its notices and SBOM"
end

# A project that lists a shared plugin at an https URL, which a Git
# setting in a home folder of the task's own sends to a repository in a
# temporary folder, so that no request leaves the computer. The app
# fetches it into a cache folder of the task's own, uses it, and then,
# with the repository gone, uses the copy without a fetch. PATH holds only
# Git's folder.
task "build:check:shared", [:app] do |_, arguments|
  app = File.expand_path(arguments.fetch(:app))
  url = "https://example.test/OWNER/signatures"
  plugin = %(artifact "doc" {\n  primary "{path}.md"\n  piece "note" "{path}.txt"\n}\n) +
    %(policy "has-note" {\n  applies-to "doc"\n  rule "piece-exists" piece="note"\n}\n)
  finder = CrossLint::Adapters::ProcessHelpers.new(err: $stderr, debug: false)
  git = File.dirname(finder.find("git") || abort("rake build:check: no git on the PATH"))
  fetching = "crosslint: fetching #{url} at v1.0.0"
  violation = "a.md: no note file at a.txt (signatures/has-note)"
  Dir.mktmpdir do |base|
    origin = File.join(base, "origin", "signatures")
    files = {File.join(origin, "plugin.kdl") => plugin, File.join(base, "home", ".gitconfig") => %([url "file:///#{origin.delete_prefix("/")}"]\n\tinsteadOf = #{url}\n),
             File.join(base, "project", ".config/crosslint/config.kdl") => %(plugin "#{url}" ref="v1.0.0"\n), File.join(base, "project", "a.md") => ""}
    files.each do |file, text|
      FileUtils.mkdir_p(File.dirname(file))
      File.binwrite(file, text)
    end
    Bundler.with_unbundled_env do
      settings = %w[-c user.name=CrossLint -c user.email=crosslint@example.test -c commit.gpgsign=false -c tag.gpgsign=false]
      [%w[init -q -b main], %w[add -A], %w[commit -q -m one], %w[tag v1.0.0]].each do |command|
        system("git", *settings, *command, chdir: origin) || abort("rake build:check: git #{command.first} failed")
      end
      system("git", "init", "-q", chdir: File.join(base, "project")) || abort("rake build:check: git init failed")
      home = File.join(base, "home")
      cache = File.join(base, "cache")
      env = {"PATH" => git, "HOME" => home, "USERPROFILE" => home, "XDG_CACHE_HOME" => cache, "LOCALAPPDATA" => cache}
      [[true, "fetches a shared plugin"], [false, "uses the copy of a shared plugin, with no fetch"]].each do |fetches, what|
        FileUtils.rm_rf(File.join(base, "origin")) unless fetches
        actual = IO.popen(env, [app, "check", "-C", File.join(base, "project")], err: %i[child out], &:read)
        lines = actual.lines(chomp: true)
        abort "rake build:check: #{app} check exited with #{$?.exitstatus}, not 1:\n#{actual}" unless $?.exitstatus == 1
        abort "rake build:check: #{app} check printed:\n#{actual}" unless lines.include?(violation) && lines.include?(fetching) == fetches

        puts "#{app} check: #{what}"
      end
    end
  end
end

# A project that lists the built-in Angular plugin, which the app
# carries, with a component that has SCSS and no spec, and a stub that
# lacks its input, which the plugin's helper reads on Node with the
# ts-morph the app carries in the plugin's node_modules, so the project
# installs no package. PATH holds only the folders of Git and Node.
task "build:check:angular", [:app] do |_, arguments|
  app = File.expand_path(arguments.fetch(:app))
  component = %(import { Component, input } from '@angular/core';\n\n@Component({ selector: 'app-card', template: '' })\n)
  files = {
    ".config/crosslint/config.kdl" => %(plugin "angular"\n),
    ".gitignore" => "node_modules/\n",
    "tsconfig.json" => %({"include": ["src/**/*.ts"]}\n),
    "src/app/card/card.component.ts" => %(#{component}export class CardComponent {\n  title = input('');\n}\n),
    "src/app/card/card.component.stub.ts" => %(#{component}export class CardComponentStub {}\n),
    "src/app/card/card.component.i.d.ts" => %(export interface CardApi {\n  title: unknown;\n}\n),
    "src/app/card/card.component.scss" => ""
  }
  finder = CrossLint::Adapters::ProcessHelpers.new(err: $stderr, debug: false)
  path = %w[git node].map { |command| File.dirname(finder.find(command) || abort("rake build:check: no #{command} on the PATH")) }.uniq
  Dir.mktmpdir do |project|
    files.each do |file, text|
      FileUtils.mkdir_p(File.dirname(File.join(project, file)))
      File.binwrite(File.join(project, file), text)
    end
    Bundler.with_unbundled_env do
      system("git", "init", "-q", chdir: project) || abort("rake build:check: git init failed")
      actual = IO.popen({"PATH" => path.join(File::PATH_SEPARATOR)}, [app, "check", "-C", project], err: %i[child out], &:read)
      expected = "src/app/card/card.component.ts: warning: scss file exists at src/app/card/card.component.scss (angular/prefer-css-over-scss)\n" \
        "src/app/card/card.component.ts: no spec file at src/app/card/card.component.spec.ts (angular/spec-exists)\n" \
        "src/app/card/card.component.ts: stub missing input: title (angular/stub-matches-component)\n" \
        "crosslint: checked 1 component artifact: 2 errors, 1 warning\n"
      abort "rake build:check: #{app} check exited with #{$?.exitstatus}, not 1:\n#{actual}" unless $?.exitstatus == 1
      abort "rake build:check: #{app} check printed:\n#{actual}" unless actual == expected

      puts "#{app} check: runs the built-in Angular plugin and its helper"
    end
  end
end

# A project that lists the built-in debt plugin, which the app carries,
# and whose debt file, in the form crosslint debt update writes, with
# the piece's name as the detail, accepts its one violation; then a
# second violation, which the plugin's command, crosslint debt update,
# writes to the debt file. PATH holds only Git's folder.
task "build:check:debt", [:app] do |_, arguments|
  app = File.expand_path(arguments.fetch(:app))
  files = {
    ".config/crosslint/config.kdl" => %(plugin "debt"\nplugin ".config/crosslint/docs"\n),
    ".config/crosslint/docs/plugin.kdl" => %(artifact "doc" {\n  primary "{path}.md"\n  piece "note" "{path}.txt"\n}\n) +
      %(policy "has-note" {\n  applies-to "doc"\n  rule "piece-exists" piece="note"\n}\n),
    ".config/crosslint/debt.tsv" => "Rule\tArtifact\tComment\tDetail\r\ndocs/has-note\ta.md\tlater\tnote\r\n",
    "a.md" => ""
  }
  finder = CrossLint::Adapters::ProcessHelpers.new(err: $stderr, debug: false)
  git = File.dirname(finder.find("git") || abort("rake build:check: no git on the PATH"))
  Dir.mktmpdir do |project|
    files.each do |file, text|
      FileUtils.mkdir_p(File.dirname(File.join(project, file)))
      File.binwrite(File.join(project, file), text)
    end
    Bundler.with_unbundled_env do
      system("git", "init", "-q", chdir: project) || abort("rake build:check: git init failed")
      actual = IO.popen({"PATH" => git}, [app, "check", "-C", project], err: %i[child out], &:read)
      expected = "crosslint: checked 1 doc artifact: 1 accepted as debt\n"
      abort "rake build:check: #{app} check exited with #{$?.exitstatus}, not 0:\n#{actual}" unless $?.success?
      abort "rake build:check: #{app} check printed:\n#{actual}" unless actual == expected

      puts "#{app} check: runs the built-in debt plugin"
      File.binwrite(File.join(project, "b.md"), "")
      [
        [["check"], 1, "b.md: no note file at b.txt (docs/has-note)\ncrosslint: checked 2 doc artifacts: 1 error, 1 accepted as debt\n", "fails for a violation the debt file lacks"],
        [["debt", "update"], 0, "crosslint: wrote .config/crosslint/debt.tsv: 1 entry added, 0 removed\ncrosslint: checked 2 doc artifacts: 2 accepted as debt\n", "writes the debt file"],
        [["check"], 0, "crosslint: checked 2 doc artifacts: 2 accepted as debt\n", "passes with the debt file it wrote"]
      ].each do |words, status, output, what|
        actual = IO.popen({"PATH" => git}, [app, *words, "-C", project], err: %i[child out], &:read)
        abort "rake build:check: #{app} #{words.join(" ")} exited with #{$?.exitstatus}, not #{status}:\n#{actual}" unless $?.exitstatus == status
        abort "rake build:check: #{app} #{words.join(" ")} printed:\n#{actual}" unless actual == output

        puts "#{app} #{words.join(" ")}: #{what}"
      end
    end
  end
end

# A project whose rules in Ruby run on the app's Ruby, the way an app
# loads gems: one plugin's rule asks a helper that runs on sh, one's
# requires a gem the app wasn't built with, and one's requires
# bundler/inline. PATH holds only the folders of Git and sh.
task "build:check:plugins", [:app] do |_, arguments|
  app = File.expand_path(arguments.fetch(:app))
  rule = ->(name, body) { %(class #{name} < CrossLint::Rule\n  def check(artifact)\n    #{body}\n  end\nend\n) }
  plugin = ->(rule_name, extra = "") { %(artifact "doc" {\n  primary "{path}.md"\n}\nhelper "rule" command=(crosslint)"ruby" file="rule.rb"\nrule "#{rule_name}" helper="rule"\n#{extra}policy "p" {\n  applies-to "doc"\n  rule "#{rule_name}"\n}\n) }
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

# The environment a helper of the built app gets is the one the app was
# started with: what the helper's `env` lists is what `env` lists when sh
# starts with that environment, which has RUBYOPT, GEM_HOME and
# BUNDLE_GEMFILE set, and a PATH of the folders of Git and sh alone. The
# launcher's own settings for the Ruby it carries, saved and put back,
# must not show. sh sets PWD, OLDPWD, SHLVL and _ itself, and MSYS2's
# entries that start with "!" hold each drive's current folder.
task "build:check:environment", [:app] do |_, arguments|
  app = File.expand_path(arguments.fetch(:app))
  files = {
    ".config/crosslint/config.kdl" => %(plugin ".config/crosslint/dumps"\n),
    ".config/crosslint/dumps/plugin.kdl" => %(artifact "doc" {\n  primary "{path}.md"\n}\nhelper "dumps" command=(crosslint)"ruby" file="rule.rb"\nrule "dumps" helper="dumps"\n) +
      %(helper "dumper" command="sh" file="dumper.sh"\npolicy "p" {\n  applies-to "doc"\n  rule "dumps"\n}\n),
    ".config/crosslint/dumps/rule.rb" => %(class Dumps < CrossLint::Rule\n  def check(artifact)\n    helper("dumper").call("hi")\n    []\n  end\nend\n),
    ".config/crosslint/dumps/dumper.sh" => %(env > helper-env.txt\nread -r line\necho '{}'\n),
    "a.md" => ""
  }
  finder = CrossLint::Adapters::ProcessHelpers.new(err: $stderr, debug: false)
  sh = finder.find("sh") || abort("rake build:check: no sh on the PATH")
  folders = [finder.find("git") || abort("rake build:check: no git on the PATH"), sh].map { |program| File.dirname(program) }.uniq
  # None of these values is a path, which MSYS2 would convert.
  started = {"PATH" => folders.join(File::PATH_SEPARATOR), "RUBYOPT" => "-W0", "GEM_HOME" => "crosslint-check-gem-home",
             "BUNDLE_GEMFILE" => "crosslint-check-gemfile", "CROSSLINT_CHECK" => "kept"}
  listed = lambda do |text|
    text.lines(chomp: true).filter_map { |line| line.split("=", 2) if line.include?("=") && !line.start_with?("!") }.to_h.except("PWD", "OLDPWD", "SHLVL", "_")
  end
  Dir.mktmpdir do |project|
    files.each do |file, text|
      FileUtils.mkdir_p(File.dirname(File.join(project, file)))
      File.binwrite(File.join(project, file), text)
    end
    Bundler.with_unbundled_env do
      system("git", "init", "-q", chdir: project) || abort("rake build:check: git init failed")
      expected = listed.call(IO.popen(started, [sh, "-c", "env"], &:read))
      actual = IO.popen(started, [app, "check", "-C", project], err: %i[child out], &:read)
      abort "rake build:check: #{app} check exited with #{$?.exitstatus}, not 0:\n#{actual}" unless $?.success?

      seen = listed.call(File.read(File.join(project, "helper-env.txt")))
      differences = (expected.keys | seen.keys).reject { |name| expected[name] == seen[name] }
      unless differences.empty?
        abort "rake build:check: a helper of #{app} got an environment that isn't the one it was started with, in:\n" +
          differences.map { |name| "  #{name}: started with #{expected[name].inspect}, the helper got #{seen[name].inspect}" }.join("\n")
      end

      puts "#{app} check: starts a helper with the environment it was started with"
    end
  end
end
