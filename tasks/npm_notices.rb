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
#   ruby tasks/npm_notices.rb DIST
#
# DIST is the folder Fledge built into. Each archive in it is unpacked
# beside it already, as Fledge leaves it; this packs it again with the
# notices, and unpacks the archive to check what it holds. Run it with
# Fledge's bundle, for Fledge::Archive.

require "json"
require "open3"
require "digest"

module NpmNotices
  # A package in a node_modules folder: its name and version, the license
  # its package.json declares, and where its folder and its license files
  # are, as paths from the app's folder.
  Package = Data.define(:name, :version, :license, :folder, :license_files)

  class Failure < StandardError; end

  LICENSE_FILE = /\A(licen[cs]e|notice|copying|unlicense)/i
  HEADING = "NPM PACKAGES THE APP CARRIES"
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

  # Writes the packages of the app folder +app+ into its notices and its
  # SBOM. +sbom+ gives the SPDX document that lists the packages a
  # package-lock.json locks, for the folder that holds the lockfile.
  def add(app, sbom: method(:npm_sbom))
    found = installed(app)
    return if found.empty?

    documents = lockfile_folders(app, found).to_h { |folder| [folder, sbom.call(File.join(app, folder))] }
    check_lockfiles_match(found, documents)
    File.binwrite(File.join(app, NOTICES), with_notices(File.binread(File.join(app, NOTICES)), found, documents))
    File.binwrite(File.join(app, SBOM), "#{JSON.pretty_generate(with_sbom(JSON.parse(File.binread(File.join(app, SBOM))), documents))}\n")
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

  def with_notices(text, found, documents)
    raise Failure, "#{NOTICES} has a #{HEADING} section already" if text.include?(HEADING)

    sources = documents.values.flat_map { |document| locked_packages(document) }.to_h { |package| [[package["name"], package["versionInfo"]], package["downloadLocation"]] }
    entries = found.map { |package| entry(package, sources.fetch([package.name, package.version])) }
    section = "#{HEADING}\n\nThe app carries these npm packages, which npm installed from the package-lock.json beside each node_modules folder.\n" \
      "Each package keeps its license files in its own folder, at the path in its entry.\n\n#{entries.join("\n")}"
    raise Failure, "#{NOTICES} has no LICENSE TEXTS heading to put the npm packages before" unless text.match?(/^LICENSE TEXTS$/)

    text.sub(/^LICENSE TEXTS$/) { "#{section}\n\nLICENSE TEXTS".b }
  end

  def entry(package, source)
    raise Failure, "#{package.folder} declares no license" unless package.license
    raise Failure, "#{package.folder} has no license file" if package.license_files.empty?

    "#{package.name} (npm package)\n  Version: #{package.version}\n  License: #{package.license}\n  Ships as: files under #{package.folder}\n" \
      "  Source: #{source}\n  License text: #{package.license_files.join(", ")}\n"
  end

  # The SBOM +document+ with the packages of each npm SBOM in
  # +documents+ (by the folder of its lockfile) and what they depend on.
  def with_sbom(document, documents)
    added = documents.flat_map { |folder, npm| npm.fetch("packages").map { |package| located(package, folder) } }
    taken = document.fetch("packages").map { |package| package["SPDXID"] }
    clash = added.map { |package| package["SPDXID"] }.tally.select { |id, count| count > 1 || taken.include?(id) }.keys
    raise Failure, "#{SBOM} would have two packages with the id #{clash.first}" unless clash.empty?

    npm = documents.values
    document.merge(
      "creationInfo" => document.fetch("creationInfo").merge("creators" => (document.dig("creationInfo", "creators") + npm.flat_map { |each| each.dig("creationInfo", "creators") }).uniq),
      "documentNamespace" => "#{document.fetch("documentNamespace")}-npm-#{Digest::SHA256.hexdigest(JSON.generate(added))[0, 16]}",
      "packages" => document.fetch("packages") + added,
      "relationships" => document.fetch("relationships") + npm.flat_map { |each| each.fetch("relationships") }
    )
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
    sbom = JSON.parse(File.binread(File.join(app, SBOM))).fetch("packages")
    installed(app).flat_map do |package|
      label = "#{package.name} #{package.version} (#{package.license})"
      listed = notices.include?("#{package.name} (npm package)\n  Version: #{package.version}\n  License: #{package.license}\n".b)
      found = sbom.any? { |each| each["name"] == package.name && each["versionInfo"] == package.version && each["licenseDeclared"] == package.license }
      [("#{NOTICES} lacks #{label}" unless listed), ("#{SBOM} lacks #{label}" unless found)].compact
    end
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
    puts "npm_notices.rb: #{file} lists the npm packages it carries"
  end
end
