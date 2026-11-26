# frozen_string_literal: true

# CrossLint isn't published as a gem. This gemspec lists CrossLint's
# program and gems for Bundler, and for Fledge, which builds the app from
# it.
Gem::Specification.new do |spec|
  spec.name = "cross_lint"
  # The version crosslint.usage.kdl gives, read with a pattern so that
  # evaluating the gemspec loads no gem.
  spec.version = File.read(File.expand_path("crosslint.usage.kdl", __dir__))[/^version "([^"]+)"$/, 1]
  spec.authors = ["setdef"]
  spec.summary = "Check the rules that span files"
  spec.homepage = "https://github.com/setdef/CrossLint"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.1.0.a"

  # The built-in plugins' folders ship in the app beside lib/.
  spec.files = Dir.chdir(__dir__) { Dir["crosslint.usage.kdl", "exe/*", "lib/**/*.rb", "plugins/**/*", "LICENSE"] }
  spec.bindir = "exe"
  spec.executables = ["crosslint"]
  spec.require_paths = ["lib"]

  spec.add_dependency "kdl", "~> 2.2"
end
