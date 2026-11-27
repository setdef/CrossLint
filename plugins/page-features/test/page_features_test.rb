# frozen_string_literal: true

require "test_helper"
require "open3"

# The page-features plugin, listed as a shared plugin from its folder of
# this repository, on projects the tests write.
class PageFeaturesTest < Minitest::Test
  URL = "https://github.com/setdef/CrossLint"

  def setup
    @root = Dir.mktmpdir("crosslint")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_asks_for_a_feature_file_at_the_matching_path_of_each_page_by_default
    %w[src/pages/home.tsx src/pages/admin/users.tsx src/pages/admin/roles.tsx features/home.feature features/admin/users.feature
      src/components/button.tsx].each { write(@root, it, "") }
    result = check

    assert_equal [["src/pages/admin/roles.tsx", "page", "feature-exists", "no feature file at features/admin/roles.feature"]], findings(result)
    assert_equal "checked 3 page artifacts: 1 error", result.summary.line
  end

  def test_finds_pages_and_their_features_where_the_settings_say
    %w[web/src/screens/cart/CartScreen.tsx web/src/screens/cart/CartScreen.test.tsx web/src/screens/cart/useCart.ts
      web/src/screens/profile/ProfileScreen.tsx specs/screens/cart/CartScreen.feature].each { write(@root, it, "") }
    result = check(%(page "./web/src/screens/{path}Screen.tsx"\n  feature "specs/screens/{path}Screen.feature"))

    assert_equal [["web/src/screens/profile/ProfileScreen.tsx", "page", "feature-exists", "no feature file at specs/screens/profile/ProfileScreen.feature"]],
      findings(result)
    assert_equal "checked 2 page artifacts: 1 error", result.summary.line
  end

  def test_takes_a_feature_pattern_with_fewer_placeholders_than_the_page_pattern
    write(@root, "app/a/one/page.tsx", "")
    write(@root, "features/one.feature", "")

    assert_equal "checked 1 page artifact: no violations", check(%(page "app/{name}/{path}/page.tsx"\n  feature "features/{path}.feature")).summary.line
  end

  def test_warns_when_no_file_matches_the_page_pattern
    write(@root, "README.md", "")

    assert_equal [%(no file matches "src/pages/{path}.tsx", the files of artifact "page")], check.notices.map(&:message)
  end

  def test_refuses_a_setting_that_isnt_one_path_pattern_inside_the_project
    inside = "takes a path pattern inside the project, relative to its root, not"
    {%(page "a/{path}.tsx"\n  page "b/{path}.tsx") => [3, "page is set twice; the first is on line 2"],
     %(page "a" "b") => [2, %(page takes one path pattern and nothing else, as in page "src/pages/{path}.tsx")],
     %(feature 1) => [2, %(feature takes one path pattern and nothing else, as in feature "features/{path}.feature")],
     %(page "a" x=1) => [2, %(page takes one path pattern and nothing else, as in page "src/pages/{path}.tsx")],
     %(page "a" { b; }) => [2, %(page takes one path pattern and nothing else, as in page "src/pages/{path}.tsx")],
     %(page "") => [2, %(page #{inside} "")],
     %(page "/src/{path}.tsx") => [2, %(page #{inside} "/src/{path}.tsx")],
     %(page "C:/src/{path}.tsx") => [2, %(page #{inside} "C:/src/{path}.tsx")],
     %(feature "../features/{path}.feature") => [2, %(feature #{inside} "../features/{path}.feature")],
     %(page "src/{nam}.tsx") => [2, %(page takes a path pattern, and path pattern "src/{nam}.tsx" has unknown placeholder "{nam}", did you mean "{name}"?)],
     %(page "src/{name}.tsx") => [2, %(feature has {path}, which page "src/{name}.tsx" doesn't, so a page gives it no value)],
     %(page "src/{name}.tsx"\n  feature "f/{path}/{name}.feature") =>
       [3, %(feature has {path}, which page "src/{name}.tsx" doesn't, so a page gives it no value)]}.each do |settings, (line, message)|
      mistake = assert_raises(CrossLint::Core::Mistake, settings) { check(settings) }

      assert_equal [".config/crosslint/config.kdl", line, message], [mistake.file, mistake.line, mistake.message], settings
    end
  end

  private

  def check(settings = nil)
    block = settings ? " {\n  #{settings}\n}" : ""
    write(@root, ".config/crosslint/config.kdl", %(plugin "#{URL}" ref="v0.1.0" path="plugins/page-features"#{block}\n))
    Open3.capture3("git", "init", "-q", chdir: @root) unless File.directory?(File.join(@root, ".git"))
    repository = CrossLint::Adapters::MemorySharedPlugins::Repository.new(tags: {"v0.1.0" => ROOT}, branches: [], commits: {})
    shared_plugins = CrossLint::Adapters::MemorySharedPlugins.new({URL => repository}, err: StringIO.new)
    CrossLint::App.new(plugin_ruby: LoadedPlugins::PluginRuby.new, shared_plugins:).check(@root)
  end

  def findings(result) = result.violations.map { [it.artifact, it.role, it.policy, it.message] }
end
