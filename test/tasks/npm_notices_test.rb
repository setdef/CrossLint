# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../tasks/npm_notices"

# tasks/npm_notices.rb on an app folder as Fledge leaves one: the notices
# and the SBOM it wrote for the runtime, and the app's own folder, with
# the packages rake packages installed in a plugin's node_modules.
class NpmNoticesTest < Minitest::Test
  include TestHelper

  PLUGIN = "app/plugins/example"
  NOTICES = "Third-party software in this app\n\n\nCOMPONENTS\n\nRuby\n  Version: 4.1.0\n\n\nLICENSE TEXTS\n\n=== ruby/COPYING\n\nRuby's license\n"

  def setup
    @app = Dir.mktmpdir("npm-notices")
    write(@app, "notices/NOTICES.txt", NOTICES)
    write(@app, "notices/sbom.spdx.json", JSON.pretty_generate(runtime_sbom))
    write(@app, "#{PLUGIN}/package-lock.json", "{}")
    install("ts-morph", "28.0.0", license: "MIT")
    install("@ts-morph/common", "0.29.1", license: "MIT")
  end

  def teardown
    FileUtils.remove_entry(@app)
  end

  def test_finds_each_package_in_a_node_modules_folder_a_scoped_one_and_one_in_a_packages_own_node_modules
    install("minimatch", "11.0.9", license: "BlueOak-1.0.0", at: "#{PLUGIN}/node_modules/ts-morph/node_modules")

    assert_equal [["@ts-morph/common", "0.29.1"], ["ts-morph", "28.0.0"], ["minimatch", "11.0.9"]],
      NpmNotices.installed(@app).map { |package| [package.name, package.version] }
  end

  def test_gives_each_package_its_folder_and_its_license_files_as_paths_from_the_app
    write(@app, "#{PLUGIN}/node_modules/ts-morph/NOTICE.txt", "Notice")
    write(@app, "#{PLUGIN}/node_modules/ts-morph/README.md", "Not a license")

    package = NpmNotices.installed(@app).find { |each| each.name == "ts-morph" }

    assert_equal ["#{PLUGIN}/node_modules/ts-morph", ["#{PLUGIN}/node_modules/ts-morph/LICENSE", "#{PLUGIN}/node_modules/ts-morph/NOTICE.txt"]],
      [package.folder, package.license_files]
  end

  def test_leaves_out_what_npm_keeps_in_node_modules_besides_packages
    write(@app, "#{PLUGIN}/node_modules/.package-lock.json", "{}")
    write(@app, "#{PLUGIN}/node_modules/.bin/tool", "")

    assert_equal %w[@ts-morph/common ts-morph], NpmNotices.installed(@app).map(&:name)
  end

  def test_finds_the_packages_of_every_node_modules_folder_in_the_app
    install("left-pad", "1.3.0", license: "WTFPL", at: "app/docs/node_modules")

    assert_includes NpmNotices.installed(@app).map(&:name), "left-pad"
  end

  def test_reads_the_license_of_an_old_package_from_its_object_or_its_list
    install("old", "1.0.0", manifest: {"license" => {"type" => "ISC"}})
    install("older", "1.0.0", manifest: {"licenses" => [{"type" => "MIT"}, {"type" => "Apache-2.0"}]})
    install("none", "1.0.0", manifest: {})

    assert_equal [["none", nil], ["old", "ISC"], ["older", "MIT OR Apache-2.0"]],
      NpmNotices.installed(@app).map { |package| [package.name, package.license] }.reject { |name, _| name.start_with?("@", "ts-") }.sort
  end

  def test_refuses_a_folder_in_node_modules_that_is_no_package
    FileUtils.mkdir_p(File.join(@app, PLUGIN, "node_modules/stray"))

    error = assert_raises(NpmNotices::Failure) { NpmNotices.installed(@app) }

    assert_equal "#{PLUGIN}/node_modules/stray has no package.json", error.message
  end

  def test_puts_each_package_in_the_notices_before_the_license_texts_in_the_form_of_the_runtimes_gems
    NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0"))

    notices = File.binread(File.join(@app, "notices/NOTICES.txt"))

    assert_equal <<~SECTION, notices[/NPM PACKAGES THE APP CARRIES.*?(?=\n\nLICENSE TEXTS)/m]
      NPM PACKAGES THE APP CARRIES

      The app carries these npm packages, which npm installed from the package-lock.json beside each node_modules folder.
      Each package keeps its license files in its own folder, at the path in its entry.

      @ts-morph/common (npm package)
        Version: 0.29.1
        License: MIT
        Ships as: files under #{PLUGIN}/node_modules/@ts-morph/common
        Source: https://registry.npmjs.org/@ts-morph/common/-/common-0.29.1.tgz
        License text: #{PLUGIN}/node_modules/@ts-morph/common/LICENSE

      ts-morph (npm package)
        Version: 28.0.0
        License: MIT
        Ships as: files under #{PLUGIN}/node_modules/ts-morph
        Source: https://registry.npmjs.org/ts-morph/-/ts-morph-28.0.0.tgz
        License text: #{PLUGIN}/node_modules/ts-morph/LICENSE
    SECTION
    assert notices.start_with?(NOTICES.split("LICENSE TEXTS").first)
    assert notices.end_with?("LICENSE TEXTS\n\n=== ruby/COPYING\n\nRuby's license\n")
  end

  def test_adds_the_packages_of_the_lockfile_to_the_sbom_with_where_the_app_has_each
    NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0"))

    added = JSON.parse(File.binread(File.join(@app, "notices/sbom.spdx.json")))["packages"].drop(1)

    assert_equal [["example-plugin", "Ships as: files under #{PLUGIN}"],
      ["@ts-morph/common", "Ships as: files under #{PLUGIN}/node_modules/@ts-morph/common"],
      ["ts-morph", "Ships as: files under #{PLUGIN}/node_modules/ts-morph"]], added.map { |package| package.values_at("name", "comment") }
  end

  def test_keeps_the_runtimes_packages_and_relationships_and_adds_the_lockfiles
    NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0"))

    sbom = JSON.parse(File.binread(File.join(@app, "notices/sbom.spdx.json")))

    assert_equal [%w[SPDXRef-Package-runtime SPDXRef-Package-example-plugin SPDXRef-Package-ts-morph.common-0.29.1 SPDXRef-Package-ts-morph-28.0.0],
      [["SPDXRef-DOCUMENT", "DESCRIBES", "SPDXRef-Package-runtime"], ["SPDXRef-DOCUMENT", "DESCRIBES", "SPDXRef-Package-example-plugin"],
        ["SPDXRef-Package-ts-morph.common-0.29.1", "DEPENDENCY_OF", "SPDXRef-Package-example-plugin"],
        ["SPDXRef-Package-ts-morph-28.0.0", "DEPENDENCY_OF", "SPDXRef-Package-example-plugin"]]],
      [sbom["packages"].map { |package| package["SPDXID"] },
        sbom["relationships"].map { |each| each.values_at("spdxElementId", "relationshipType", "relatedSpdxElement") }]
  end

  def test_names_npm_as_a_creator_of_the_sbom_and_gives_the_changed_document_a_namespace_of_its_own
    NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0"))

    sbom = JSON.parse(File.binread(File.join(@app, "notices/sbom.spdx.json")))

    assert_equal ["Tool: fledge-license-audit-0.17.0", "Tool: npm/cli-11.20.0"], sbom["creationInfo"]["creators"]
    assert_match(%r{\Ahttps://example.test/spdx/runtime-[0-9a-f]{16}\z}, sbom["documentNamespace"].sub("-npm", ""))
    refute_equal runtime_sbom["documentNamespace"], sbom["documentNamespace"]
  end

  def test_changes_nothing_in_an_app_with_no_node_modules
    FileUtils.rm_rf(File.join(@app, PLUGIN, "node_modules"))

    NpmNotices.add(@app, sbom: ->(*) { flunk "asked for an SBOM" })

    assert_equal NOTICES, File.binread(File.join(@app, "notices/NOTICES.txt"))
  end

  def test_keeps_the_bytes_of_notices_that_are_not_ascii
    write(@app, "notices/NOTICES.txt", "Zoë's notice, and a CRLF line\r\n\n\nLICENSE TEXTS\n")

    NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0"))

    notices = File.binread(File.join(@app, "notices/NOTICES.txt"))

    assert notices.start_with?("Zoë's notice, and a CRLF line\r\n\n\nNPM PACKAGES THE APP CARRIES\n".b)
    assert notices.end_with?("\n\n\nLICENSE TEXTS\n".b)
    assert_empty NpmNotices.problems(@app)
  end

  def test_refuses_node_modules_with_no_lockfile_beside_it
    File.delete(File.join(@app, PLUGIN, "package-lock.json"))

    error = assert_raises(NpmNotices::Failure) { NpmNotices.add(@app, sbom: sbom_of({})) }

    assert_equal "#{PLUGIN}/node_modules has packages, and no #{PLUGIN}/package-lock.json says where they come from", error.message
  end

  def test_refuses_a_lockfile_whose_packages_are_not_the_ones_in_node_modules
    error = assert_raises(NpmNotices::Failure) { NpmNotices.add(@app, sbom: sbom_of("ts-morph" => "28.0.0", "typescript" => "6.0.3")) }

    assert_equal %(#{PLUGIN}/package-lock.json locks [["ts-morph", "28.0.0"], ["typescript", "6.0.3"]], ) +
      %(and #{PLUGIN}/node_modules holds [["@ts-morph/common", "0.29.1"], ["ts-morph", "28.0.0"]]), error.message
  end

  def test_refuses_a_package_that_declares_no_license
    install("none", "1.0.0", manifest: {})

    error = assert_raises(NpmNotices::Failure) { NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0", "none" => "1.0.0")) }

    assert_equal "#{PLUGIN}/node_modules/none declares no license", error.message
  end

  def test_refuses_a_package_with_no_license_file
    File.delete(File.join(@app, PLUGIN, "node_modules/ts-morph/LICENSE"))

    error = assert_raises(NpmNotices::Failure) { NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0")) }

    assert_equal "#{PLUGIN}/node_modules/ts-morph has no license file", error.message
  end

  def test_refuses_notices_that_have_the_packages_already
    sbom = sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0")
    NpmNotices.add(@app, sbom:)

    error = assert_raises(NpmNotices::Failure) { NpmNotices.add(@app, sbom:) }

    assert_equal "notices/NOTICES.txt has a NPM PACKAGES THE APP CARRIES section already", error.message
  end

  def test_refuses_notices_with_no_license_texts_heading
    write(@app, "notices/NOTICES.txt", "Third-party software\n")

    error = assert_raises(NpmNotices::Failure) { NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0")) }

    assert_equal "notices/NOTICES.txt has no LICENSE TEXTS heading to put the npm packages before", error.message
  end

  def test_refuses_a_package_id_the_sbom_has_already
    write(@app, "notices/sbom.spdx.json", JSON.pretty_generate(runtime_sbom.merge("packages" => [{"SPDXID" => "SPDXRef-Package-ts-morph-28.0.0"}])))

    error = assert_raises(NpmNotices::Failure) { NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0")) }

    assert_equal "notices/sbom.spdx.json would have two packages with the id SPDXRef-Package-ts-morph-28.0.0", error.message
  end

  def test_finds_every_package_missing_from_the_notices_and_the_sbom_of_an_app_nothing_was_added_to
    assert_equal ["notices/NOTICES.txt lacks @ts-morph/common 0.29.1 (MIT)", "notices/sbom.spdx.json lacks @ts-morph/common 0.29.1 (MIT)",
      "notices/NOTICES.txt lacks ts-morph 28.0.0 (MIT)", "notices/sbom.spdx.json lacks ts-morph 28.0.0 (MIT)"], NpmNotices.problems(@app)
  end

  def test_finds_no_package_missing_once_the_packages_were_added
    NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0"))

    assert_empty NpmNotices.problems(@app)
  end

  def test_finds_a_package_the_app_carries_that_the_lockfile_it_was_added_from_did_not_list
    NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0"))
    install("minimatch", "11.0.9", license: "BlueOak-1.0.0")

    assert_equal ["notices/NOTICES.txt lacks minimatch 11.0.9 (BlueOak-1.0.0)", "notices/sbom.spdx.json lacks minimatch 11.0.9 (BlueOak-1.0.0)"], NpmNotices.problems(@app)
  end

  def test_finds_a_package_whose_version_or_license_the_notices_or_the_sbom_give_otherwise
    NpmNotices.add(@app, sbom: sbom_of("@ts-morph/common" => "0.29.1", "ts-morph" => "28.0.0"))
    notices = File.join(@app, "notices/NOTICES.txt")
    File.binwrite(notices, File.binread(notices).sub("Version: 28.0.0", "Version: 27.0.0"))
    sbom = File.join(@app, "notices/sbom.spdx.json")
    File.binwrite(sbom, File.binread(sbom).sub('"licenseDeclared": "MIT"', %("licenseDeclared": "ISC")))

    assert_equal ["notices/sbom.spdx.json lacks @ts-morph/common 0.29.1 (MIT)", "notices/NOTICES.txt lacks ts-morph 28.0.0 (MIT)"], NpmNotices.problems(@app)
  end

  def test_asks_npm_for_the_sbom_of_a_lockfile_without_reaching_a_registry_or_the_packages_of_development
    folder = File.join(@app, "locked")
    write(folder, "package.json", JSON.generate("name" => "locked", "version" => "1.0.0", "license" => "MIT",
      "dependencies" => {"left-pad" => "1.3.0"}, "devDependencies" => {"dev-only" => "2.0.0"}))
    write(folder, "package-lock.json", JSON.generate("name" => "locked", "version" => "1.0.0", "lockfileVersion" => 3, "requires" => true, "packages" => {
      "" => {"name" => "locked", "version" => "1.0.0", "license" => "MIT", "dependencies" => {"left-pad" => "1.3.0"}, "devDependencies" => {"dev-only" => "2.0.0"}},
      "node_modules/left-pad" => {"version" => "1.3.0", "resolved" => "https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz", "integrity" => "sha512-#{"A" * 86}==", "license" => "WTFPL"},
      "node_modules/dev-only" => {"version" => "2.0.0", "resolved" => "https://registry.npmjs.org/dev-only/-/dev-only-2.0.0.tgz", "integrity" => "sha512-#{"B" * 86}==", "dev" => true, "license" => "ISC"}
    }))

    document = NpmNotices.npm_sbom(folder)

    assert_equal [["locked", "1.0.0", "MIT"], ["left-pad", "1.3.0", "WTFPL"]],
      document["packages"].map { |package| package.values_at("name", "versionInfo", "licenseDeclared") }
  end

  def test_says_what_npm_printed_when_it_cannot_make_the_sbom
    error = assert_raises(NpmNotices::Failure) { NpmNotices.npm_sbom(@app) }

    assert_match(/\Anpm sbom failed in #{Regexp.escape(@app)}:\n/, error.message)
  end

  private

  def install(name, version, license: "MIT", manifest: {"license" => license}, at: "#{PLUGIN}/node_modules")
    folder = "#{at}/#{name}"
    write(@app, "#{folder}/package.json", JSON.generate({"name" => name, "version" => version}.merge(manifest)))
    write(@app, "#{folder}/LICENSE", "The #{license} License\n")
  end

  def runtime_sbom
    {"spdxVersion" => "SPDX-2.3", "SPDXID" => "SPDXRef-DOCUMENT", "name" => "runtime", "documentNamespace" => "https://example.test/spdx/runtime",
     "creationInfo" => {"created" => "2026-11-22T09:13:41Z", "creators" => ["Tool: fledge-license-audit-0.17.0"]},
     "packages" => [{"SPDXID" => "SPDXRef-Package-runtime", "name" => "runtime"}],
     "relationships" => [{"spdxElementId" => "SPDXRef-DOCUMENT", "relationshipType" => "DESCRIBES", "relatedSpdxElement" => "SPDXRef-Package-runtime"}]}
  end

  # What npm sbom answers for a lockfile that locks +locked+, a name and a
  # version for each package, under the plugin's own package.
  def sbom_of(locked)
    root = {"name" => "example-plugin", "SPDXID" => "SPDXRef-Package-example-plugin", "versionInfo" => "0.2.0", "packageFileName" => ""}
    packages = locked.map do |name, version|
      {"name" => name, "SPDXID" => "SPDXRef-Package-#{name.delete_prefix("@").tr("/", ".")}-#{version}", "versionInfo" => version, "packageFileName" => "node_modules/#{name}",
       "downloadLocation" => "https://registry.npmjs.org/#{name}/-/#{name.split("/").last}-#{version}.tgz", "licenseDeclared" => "MIT"}
    end
    document = {"creationInfo" => {"creators" => ["Tool: npm/cli-11.20.0"]}, "documentDescribes" => [root["SPDXID"]], "packages" => [root, *packages],
                "relationships" => [{"spdxElementId" => "SPDXRef-DOCUMENT", "relatedSpdxElement" => root["SPDXID"], "relationshipType" => "DESCRIBES"},
                  *packages.map { |package| {"spdxElementId" => package["SPDXID"], "relatedSpdxElement" => root["SPDXID"], "relationshipType" => "DEPENDENCY_OF"} }]}
    ->(_folder) { document }
  end
end
