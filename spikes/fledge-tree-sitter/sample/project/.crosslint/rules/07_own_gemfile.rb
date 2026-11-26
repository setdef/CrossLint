# A rule file whose project has a Gemfile of its own (here, written to a
# temporary folder): the app installs those gems with the Bundler that came
# with its Ruby, in a subprocess, then loads one from there.
require "fileutils"
require "rbconfig"
require "tmpdir"

dir = Dir.mktmpdir("own-gemfile")
File.write(File.join(dir, "Gemfile"), %(source "https://rubygems.org"\ngem "rainbow", "3.1.1"\n))
ruby = RbConfig.ruby
bundle = File.join(RbConfig::CONFIG["bindir"], "bundle#{RbConfig::CONFIG["EXEEXT"]}")
# Leave the app's own Bundler settings behind, as a subprocess should.
env = ENV.to_h.reject { |k, _| k.start_with?("BUNDLE", "RUBY") || k == "GEM_HOME" || k == "GEM_PATH" }
env["BUNDLE_GEMFILE"] = File.join(dir, "Gemfile")
env["BUNDLE_PATH"] = File.join(dir, "vendor")
ok = system(env, ruby, bundle, "install", chdir: dir, unsetenv_others: true, out: File::NULL, err: File::NULL)
raise "bundle install in a subprocess failed" unless ok

out = IO.popen(env, [ruby, bundle, "exec", ruby, "-e", 'require "rainbow"; puts Rainbow("x").red.inspect'],
               chdir: dir, unsetenv_others: true, &:read)
TsSpike.rule("own-gemfile") { |_facts| ["subprocess printed #{out.strip}"] }
FileUtils.rm_rf(dir)
