# frozen_string_literal: true

# Adds the npm packages that a built app carries to the app's notices and
# bill of materials, and checks that both list every one of them
# (rake build runs it on each archive Fledge wrote).
#
# Fledge writes notices/NOTICES.txt and notices/sbom.spdx.json for the
# runtime it copies into the app, and for nothing else. The app also
# carries the node_modules folders that rake packages installed, so each
# package there gets an entry in NOTICES.txt, in the form Fledge gives
# the runtime's gems, and a package in the SBOM, which npm sbom writes
# from the package-lock.json beside the folder. The packages come from
# the folders the app holds, never from a list.
#
# Some of those packages carry another project's code inside their own
# files, such as the TypeScript in @ts-morph/common's dist/typescript.js.
# Each such work (tasks/bundled_works.rb) gets an entry in
# both files, with its license text, and the build fails when the app
# has a license notice that the table of works doesn't know.
#
#   ruby tasks/npm_notices.rb DIST
#
# DIST is the folder Fledge built into. Each archive in it is unpacked
# beside it already, as Fledge leaves it; this packs it again with the
# notices, and unpacks the archive to check what it holds. Run it with
# Fledge's bundle, for Fledge::Archive.

require "json"
require "open3"
require "digest"
require_relative "bundled_works"

module NpmNotices
  # A package in a node_modules folder: its name and version, the license
  # its package.json declares, and where its folder and its license files
  # are, as paths from the app's folder.
  Package = Data.define(:name, :version, :license, :folder, :license_files)

  Failure = BundledWorks::Failure

  LICENSE_FILE = /\A(licen[cs]e|notice|copying|unlicense)/i
  HEADING = "NPM PACKAGES THE APP CARRIES"
  BUNDLED_HEADING = "WORKS THE NPM PACKAGES BUNDLE"
  NO_VERSION = "not stated in the files that carry it"
  NOTICES = "notices/NOTICES.txt"
  SBOM = "notices/sbom.spdx.json"

  module_function

  # Every package in the node_modules folders under the app folder +app+,
  # the folders a package holds in its own node_modules included.
  def installed(app)
    modules = Dir.glob("**/node_modules", File::FNM_DOTMATCH, base: app).reject { |path| path.match?(%r{(\A|/)node_modules/}) }
    modules.sort.flat_map { |path| packages_in(app, path) }
  end

  def packages_in(app, modules)
    names = Dir.children(File.join(app, modules)).reject { |child| child.start_with?(".") }.sort.flat_map do |child|
      child.start_with?("@") ? Dir.children(File.join(app, modules, child)).sort.map { |name| "#{child}/#{name}" } : [child]
    end
    names.flat_map do |name|
      folder = "#{modules}/#{name}"
      [package(app, folder, name), *(packages_in(app, "#{folder}/node_modules") if File.directory?(File.join(app, folder, "node_modules")))]
    end
  end

  def package(app, folder, name)
    manifest = begin
      JSON.parse(File.read(File.join(app, folder, "package.json")))
    rescue Errno::ENOENT
      raise Failure, "#{folder} has no package.json"
    end
    files = Dir.children(File.join(app, folder)).select { |child| child.match?(LICENSE_FILE) && File.file?(File.join(app, folder, child)) }.sort
    Package.new(name: manifest.fetch("name", name), version: manifest.fetch("version"), license: license(manifest),
      folder:, license_files: files.map { |file| "#{folder}/#{file}" })
  end

  # The license a package.json declares: an SPDX expression, or in an old
  # package, an object or a list of them.
  def license(manifest)
    declared = manifest["license"] || manifest["licenses"]
    declared = declared.map { |each| each.is_a?(Hash) ? each["type"] : each }.join(" OR ") if declared.is_a?(Array)
    declared = declared["type"] if declared.is_a?(Hash)
    declared unless declared.to_s.empty?
  end

  # Writes the packages of the app folder +app+, and the works they bundle
  # (BundledWorks), into its notices and its SBOM. +sbom+ gives the SPDX
  # document that lists the packages a package-lock.json locks, for the
  # folder that holds the lockfile. +release+ gives the license files of
  # a BundledWorks::Release, as BundledWorks.npm_release does, and fails
  # when the tarball isn't the one the table lists.
  def add(app, sbom: method(:npm_sbom), release: BundledWorks.method(:npm_release))
    found = installed(app)
    return if found.empty?

    documents = lockfile_folders(app, found).to_h { |folder| [folder, sbom.call(File.join(app, folder))] }
    check_lockfiles_match(found, documents)
    works = BundledWorks.find(app, found)
    unknown = BundledWorks.unknown(app, found, works)
    raise Failure, unknown.join("\n") unless unknown.empty?

    texts = works.to_h { |work| [work, work.release ? release.call(work.release) : {}] }
    File.binwrite(File.join(app, NOTICES), with_notices(File.binread(File.join(app, NOTICES)), found, documents, texts))
    File.binwrite(File.join(app, SBOM), "#{JSON.pretty_generate(with_sbom(JSON.parse(File.binread(File.join(app, SBOM))), documents, texts.keys))}\n")
  end

  # The folders that hold a package-lock.json for the node_modules
  # folders of +found+.
  def lockfile_folders(app, found)
    folders = found.map { |package| package.folder.sub(%r{/node_modules/.*}, "") }.uniq
    folders.each do |folder|
      raise Failure, "#{folder}/node_modules has packages, and no #{folder}/package-lock.json says where they come from" unless File.file?(File.join(app, folder, "package-lock.json"))
    end
    folders
  end

  # npm sbom, which reads the lockfile in +folder+ and no registry, for
  # what npm ci --omit=dev installs there.
  def npm_sbom(folder)
    output, error, status = Open3.capture3("npm", "sbom", "--sbom-format", "spdx", "--omit=dev", "--package-lock-only", "--offline", chdir: folder)
    raise Failure, "npm sbom failed in #{folder}:\n#{error}" unless status.success?

    JSON.parse(output)
  end

  # Fails when the packages a lockfile lists aren't the packages in its
  # node_modules folder: the lock and the folder disagree about what the
  # app carries.
  def check_lockfiles_match(found, documents)
    documents.each do |folder, document|
      locked = locked_packages(document).map { |package| [package["name"], package["versionInfo"]] }.sort
      here = found.select { |package| package.folder.start_with?("#{folder}/node_modules/") }.map { |package| [package.name, package.version] }.sort
      next if locked == here

      raise Failure, "#{folder}/package-lock.json locks #{locked.inspect}, and #{folder}/node_modules holds #{here.inspect}"
    end
  end

  # The packages of an npm SBOM document, less the package that has the
  # lockfile, which is the folder's own.
  def locked_packages(document) = document.fetch("packages").reject { |package| document.fetch("documentDescribes").include?(package["SPDXID"]) }

  def with_notices(text, found, documents, works)
    raise Failure, "#{NOTICES} has a #{HEADING} section already" if text.include?(HEADING)

    sources = documents.values.flat_map { |document| locked_packages(document) }.to_h { |package| [[package["name"], package["versionInfo"]], package["downloadLocation"]] }
    entries = found.map { |package| entry(package, sources.fetch([package.name, package.version])) }
    section = "#{HEADING}\n\nThe app carries these npm packages, which npm installed from the package-lock.json beside each node_modules folder.\n" \
      "Each package keeps its license files in its own folder, at the path in its entry.\n\n#{entries.join("\n")}#{bundled_section(works)}"
    raise Failure, "#{NOTICES} has no LICENSE TEXTS heading to put the npm packages before" unless text.match?(/^LICENSE TEXTS$/)

    text.sub(/^LICENSE TEXTS$/) { "#{section}\n\nLICENSE TEXTS".b } + license_texts(works).b
  end

  # The section for the works that the packages bundle, which is empty
  # when they bundle none.
  def bundled_section(works)
    return "" if works.empty?

    "\n\n#{BUNDLED_HEADING}\n\nThe npm packages above carry these works inside their files, which no package.json lists.\n" \
      "A work's license text is in the file of its entry, or below, under LICENSE TEXTS.\n\n#{works.map { |work, texts| bundled_entry(work, texts) }.join("\n")}"
  end

  def bundled_entry(work, texts)
    license_text = texts.empty? ? work.places.map { |place| "#{place.file}, in the notice at line #{place.line}" }.join("; ") : "#{texts.keys.map { |file| "#{work.folder}/#{file}" }.join(", ")}, below"
    <<~ENTRY
      #{work.work.name} (bundled work)
        Version: #{work.version || NO_VERSION}
        License: #{work.work.license}
        Copyright: #{work.copyright || "not stated in the files that carry it"}
        Bundled in: #{work.places.map(&:package).uniq.map { |package| "#{package.name} #{package.version}" }.join(", ")}
        Ships as: code in #{work.places.map(&:file).join(", ")}
        Source: #{work.source}
        License text: #{license_text}
    ENTRY
  end

  # The license files of the works that npm packages release, in the form
  # of the runtime's own, to follow LICENSE TEXTS.
  def license_texts(works)
    works.flat_map { |work, texts| texts.map { |file, text| "\n=== #{work.folder}/#{file}\n\n#{text.strip}\n" } }.join
  end

  def entry(package, source)
    raise Failure, "#{package.folder} declares no license" unless package.license
    raise Failure, "#{package.folder} has no license file" if package.license_files.empty?

    "#{package.name} (npm package)\n  Version: #{package.version}\n  License: #{package.license}\n  Ships as: files under #{package.folder}\n" \
      "  Source: #{source}\n  License text: #{package.license_files.join(", ")}\n"
  end

  # The SBOM +document+ with the packages of each npm SBOM in
  # +documents+ (by the folder of its lockfile) and what they depend on.
  # +works+ are the works the packages bundle, each a package that the
  # packages carrying it contain.
  def with_sbom(document, documents, works)
    added = documents.flat_map { |folder, npm| npm.fetch("packages").map { |package| located(package, folder) } }
    bundled = works.map { |work| bundled_package(work) }
    taken = document.fetch("packages").map { |package| package["SPDXID"] }
    clash = (added + bundled).map { |package| package["SPDXID"] }.tally.select { |id, count| count > 1 || taken.include?(id) }.keys
    raise Failure, "#{SBOM} would have two packages with the id #{clash.first}" unless clash.empty?

    npm = documents.values
    document.merge(
      "creationInfo" => document.fetch("creationInfo").merge("creators" => (document.dig("creationInfo", "creators") + npm.flat_map { |each| each.dig("creationInfo", "creators") }).uniq),
      "documentNamespace" => "#{document.fetch("documentNamespace")}-npm-#{Digest::SHA256.hexdigest(JSON.generate([added, bundled]))[0, 16]}",
      "packages" => document.fetch("packages") + added + bundled,
      "relationships" => document.fetch("relationships") + npm.flat_map { |each| each.fetch("relationships") } + works.flat_map { |work| contains(work, added) }
    )
  end

  # A work that packages bundle, as an SPDX package: SPDX 2.3 has a
  # package that contains another, and a work no lockfile locks is a
  # package of its own.
  def bundled_package(work)
    {"SPDXID" => work.spdx_id, "name" => work.work.name, "versionInfo" => work.version, "downloadLocation" => work.source, "filesAnalyzed" => false,
     "licenseDeclared" => work.work.license, "licenseConcluded" => "NOASSERTION", "copyrightText" => work.copyright || "NOASSERTION",
     "comment" => "Ships as: code in #{work.places.map(&:file).join(", ")}",
     "externalRefs" => (work.work.release ? [{"referenceCategory" => "PACKAGE-MANAGER", "referenceType" => "purl", "referenceLocator" => "pkg:npm/#{work.work.release}@#{work.version}"}] : nil)}.compact
  end

  # The relationships from each package of +added+ that carries +work+ to it.
  def contains(work, added)
    work.places.map(&:package).uniq.map do |package|
      carrier = added.find { |each| each["name"] == package.name && each["versionInfo"] == package.version }
      raise Failure, "#{SBOM} would have no package for #{package.name} #{package.version}, which carries #{work.work.name}" unless carrier

      {"spdxElementId" => carrier["SPDXID"], "relationshipType" => "CONTAINS", "relatedSpdxElement" => work.spdx_id}
    end
  end

  # An npm SBOM's +package+ with a comment that says where the app has it, as Fledge's packages do.
  def located(package, folder)
    where = [folder, package["packageFileName"].to_s].reject(&:empty?).join("/")
    package.merge("comment" => "Ships as: files under #{where}")
  end

  # What the notices and the SBOM of the app folder +app+ lack of the
  # packages it carries, as a list of sentences. It reads the folders
  # the app holds, as #installed does, and not what #add wrote.
  def problems(app)
    notices = File.binread(File.join(app, NOTICES))
    document = JSON.parse(File.binread(File.join(app, SBOM)))
    packages = installed(app)
    works = BundledWorks.find(app, packages)
    packages.flat_map { |package| package_problems(package, notices, document) } + works.flat_map { |work| work_problems(work, notices, document) } +
      BundledWorks.unknown(app, packages, works)
  end

  def package_problems(package, notices, document)
    label = "#{package.name} #{package.version} (#{package.license})"
    listed = notices.include?("#{package.name} (npm package)\n  Version: #{package.version}\n  License: #{package.license}\n".b)
    found = document.fetch("packages").any? { |each| each["name"] == package.name && each["versionInfo"] == package.version && each["licenseDeclared"] == package.license }
    [("#{NOTICES} lacks #{label}" unless listed), ("#{SBOM} lacks #{label}" unless found)].compact
  end

  # What the notices and the SBOM lack of a bundled +work+: its entry, its
  # license text when a release has it, and the SBOM's package and the
  # relationship from each package that carries it.
  def work_problems(work, notices, document)
    label = "#{work.work.name} #{work.version} (#{work.work.license})".squeeze(" ")
    listed = notices.include?("#{work.work.name} (bundled work)\n  Version: #{work.version || NO_VERSION}\n  License: #{work.work.license}\n".b)
    texted = !work.release || notices.match?(%r{^=== #{Regexp.escape(work.folder)}/licen[cs]e}i)
    packages = document.fetch("packages")
    found = packages.any? { |each| each["SPDXID"] == work.spdx_id && each["name"] == work.work.name && each["licenseDeclared"] == work.work.license }
    relationships = document.fetch("relationships").map { |each| each.values_at("spdxElementId", "relationshipType", "relatedSpdxElement") }
    related = work.places.map(&:package).uniq.all? do |package|
      carrier = packages.find { |each| each["name"] == package.name && each["versionInfo"] == package.version }
      carrier && relationships.include?([carrier["SPDXID"], "CONTAINS", work.spdx_id])
    end
    [("#{NOTICES} lacks #{label}" unless listed), ("#{NOTICES} lacks the license text of #{label}" unless texted),
      ("#{SBOM} lacks #{label}" unless found), ("#{SBOM} lacks the relationships that say each package carrying #{label} contains it" unless related)].compact
  end
end

if $PROGRAM_NAME == __FILE__
  require "fledge"
  require "tmpdir"

  dist = File.expand_path(ARGV.fetch(0))
  archives = Dir.glob("*{#{Fledge::Archive::TAR_GZ},#{Fledge::Archive::ZIP}}", base: dist).sort
  abort "npm_notices.rb: no archive in #{dist}" if archives.empty?

  archives.each do |file|
    archive = File.join(dist, file)
    folder = archive.delete_suffix(File.extname(archive)).delete_suffix(".tar")
    begin
      NpmNotices.add(folder)
      Fledge::Archive.pack(folder, to: archive)
      Fledge::Checksum.write(archive)
      Dir.mktmpdir do |unpacked|
        Fledge::Archive.unpack(archive, into: unpacked)
        missing = NpmNotices.problems(File.join(unpacked, File.basename(folder)))
        raise NpmNotices::Failure, missing.join("\n") unless missing.empty?
      end
    rescue NpmNotices::Failure => failure
      abort "npm_notices.rb: #{file}: #{failure.message}"
    end
    puts "npm_notices.rb: #{file} lists the npm packages it carries, and the works they bundle"
  end
end
