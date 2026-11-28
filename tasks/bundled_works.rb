# frozen_string_literal: true

# The works that an npm package carries inside its files, which no
# package.json lists and no lockfile locks, and what the app's notices
# and bill of materials need to say about each.
#
# A package that bundles another project's code, as @ts-morph/common
# bundles Microsoft's TypeScript, keeps that project's license in a
# comment at the top of the bundled file, or nowhere. The license may ask
# for its full text, or for a notice, to go with every copy, so tasks/
# npm_notices.rb gives each work an entry, from this table, and
# fails when the app carries a license notice that the table doesn't
# know, unless it belongs to its package (tasks/own_notices.rb).

require "json"
require "digest"
require "rubygems/package"
require "zlib"
require "open3"
require "tmpdir"
require_relative "own_notices"

module BundledWorks
  class Failure < StandardError; end

  # Where a package holds a work: +file+ is a path inside the package's
  # folder, and +marker+ is the text in it that shows the work is there.
  Carrier = Data.define(:package, :file, :marker)

  # A work: its +name+ and SPDX +license+, the +carriers+ that hold it,
  # and where its version is: +version+ is a pattern whose first group
  # matches it in a carrier's file. +source+ says where its source is,
  # with %<version>s for the version. A work with a +release+, the name
  # of an npm package, has its license text, and any notice, in that
  # package's files at the version, which the build reads from the
  # registry. A work with none has its license in the comment of each
  # carrier's file, which the app carries as it is. +integrity+ lists, for
  # each version of the release that the build has read, the sha512
  # integrity of its tarball as the registry gives it (nil for a work with
  # no release): the build fetches no tarball that differs, so a new
  # version fails until someone has looked at what it ships and lists it.
  Work = Data.define(:name, :license, :carriers, :version, :source, :release, :integrity)

  # The tarball of a +work+'s release to fetch: the npm +package+ at its
  # +version+, and the +integrity+ the table lists for it (nil when it
  # lists none).
  Release = Data.define(:work, :package, :version, :integrity)

  # One place the app holds a work: the +package+ (a NpmNotices::Package),
  # the carrier's +file+ as a path from the app's folder, and the +line+
  # the marker is on.
  Place = Data.define(:package, :file, :line)

  # A work the app carries: its +version+ (nil when no carrier says it),
  # the +copyright+ line above its notice (nil when none has one), and
  # its +places+.
  Found = Data.define(:work, :version, :copyright, :places) do
    def source = work.source.sub("%<version>s", version.to_s)

    def release = work.release && Release.new(work: work.name, package: work.release, version:, integrity: work.integrity[version])

    # The folder in the notices under which the work's license texts are.
    def folder = [work.name.downcase.gsub(/[^a-z0-9.]+/, "-"), version].compact.join("-")

    # The SPDX id of the work's package in the bill of materials.
    def spdx_id = "SPDXRef-Package-bundled-#{[work.name, version].compact.join('-').gsub(/[^A-Za-z0-9.-]+/, '-')}"
  end

  # What a work's release gives: the license texts and notices at the top
  # of its npm package, by file name.
  RELEASE_TEXT = /\A(licen[cs]e|notice|copying|unlicense|thirdpartynotice)/i
  FETCH_SECONDS = 120

  # The works known to be bundled in what Fledge's app carries.
  WORKS = [
    Work.new(
      name: "TypeScript", license: "Apache-2.0", release: "typescript",
      integrity: { "6.0.2" => "sha512-bGdAIrZ0wiGDo5l8c++HWtbaNCWTS4UTv7RaTH/ThVIgjkveJt83m74bBHMJkuCbslY8ixgLBVZJIOiQlQTjfQ==" },
      version: /^var version = "([^"]+)"/, source: "https://registry.npmjs.org/typescript/-/typescript-%<version>s.tgz",
      carriers: [
        Carrier.new("@ts-morph/common", "dist/typescript.js", /Licensed under the Apache License, Version 2\.0/),
        Carrier.new("@ts-morph/common", "lib/typescript.d.ts", /Licensed under the Apache License, Version 2\.0/),
        # The library files that TypeScript ships, lib.es5.d.ts among them,
        # which ts-morph keeps in this file as strings.
        Carrier.new("@ts-morph/common", "dist/ts-morph-common.js", /fileName: "lib\.es5\.d\.ts"/),
      ]
    ),
    Work.new(
      name: "tslib", license: "0BSD", release: nil, integrity: nil, version: nil, source: "https://github.com/microsoft/tslib",
      carriers: [
        Carrier.new("ts-morph", "dist/ts-morph.js", %r{Permission to use, copy, modify, and/or distribute this software for any}),
        Carrier.new("@ts-morph/common", "dist/ts-morph-common.js", %r{Permission to use, copy, modify, and/or distribute this software for any}),
      ]
    ),
    Work.new(
      name: "Node.js", license: "MIT", release: nil, integrity: nil, version: /extracted from Node\.js v([0-9.]+)/, source: "https://github.com/nodejs/node/tree/v%<version>s",
      carriers: [
        Carrier.new("path-browserify", "index.js", /Copyright Joyent, Inc\. and other Node contributors/),
        Carrier.new("path-browserify", "test/test-path.js", /Copyright Joyent, Inc\. and other Node contributors/),
        Carrier.new("path-browserify", "test/test-path-parse-format.js", /Copyright Joyent, Inc\. and other Node contributors/),
      ]
    ),
  ].freeze

  SOURCE = /\.(js|cjs|mjs|ts|cts|mts)\z/

  module_function

  # The works of WORKS that the +packages+ (NpmNotices::Package) in the
  # app folder +app+ carry.
  def find(app, packages, works: WORKS)
    works.filter_map { |work| located(app, work, packages) }
  end

  def located(app, work, packages)
    texts = {}
    places = work.carriers.flat_map do |carrier|
      packages.select { |package| package.name == carrier.package }.filter_map do |package|
        file = "#{package.folder}/#{carrier.file}"
        next unless File.file?(File.join(app, file))

        text = File.binread(File.join(app, file))
        match = carrier.marker.match(text) or next
        texts[file] = [text, match]
        Place.new(package:, file:, line: text[0, match.begin(0)].count("\n") + 1)
      end
    end
    return if places.empty?

    version = work.version && texts.each_value.filter_map { |text, _| text[work.version, 1] }.first
    raise Failure, "#{places.first.file} holds #{work.name}, and no file that holds it says which version" if work.release && !version

    Found.new(work:, version:, copyright: texts.each_value.filter_map { |text, match| text[0, match.end(0)].scan(/Copyright[^\r\n]*/).last }.first&.strip, places:)
  end

  # The license notices that the packages in the app carry in source
  # files that no work of +found+ is in, as a list of sentences: a work
  # that the table doesn't know has come in. A notice that belongs to its package, the
  # one its npm entry credits (OwnNotices), is none.
  def unknown(app, packages, found)
    known = found.flat_map(&:places).map(&:file)
    packages.flat_map { |package| notices_in(app, package, known) }.map do |file|
      "#{file} has a license notice of a work that tasks/bundled_works.rb doesn't know"
    end
  end

  # The source files in +package+'s folder, but its node_modules and
  # the +known+ files, that have a license notice in them that its
  # package's entry doesn't credit.
  def notices_in(app, package, known)
    folder = File.join(app, package.folder)
    credit = OwnNotices.credit(package.license, package.license_files.map { |file| File.binread(File.join(app, file)) })
    Dir.glob("**/*", File::FNM_DOTMATCH, base: folder).sort.filter_map do |path|
      file = "#{package.folder}/#{path}"
      next if known.include?(file) || path.match?(%r{(\A|/)node_modules(/|\z)}) || !path.match?(SOURCE) || !File.file?(File.join(app, file))

      text = File.binread(File.join(app, file))
      file if text.match?(OwnNotices::NOTICE) && !credit.covers?(text)
    end
  end

  # The license files at the top of the Release +release+, by file name,
  # read from the registry with npm pack: the files +RELEASE_TEXT+
  # matches, with their text. The tarball is read only when its integrity
  # is the one the release lists, so that what the archive credits is what
  # someone looked at, and not whatever the registry gives that day. +npm+
  # is the command that runs npm.
  def npm_release(release, npm: %w[npm])
    name = release.package
    version = release.version
    warn "npm_notices.rb: fetching #{name}@#{version} from the npm registry, to read its license files, for at most #{FETCH_SECONDS} seconds"
    Dir.mktmpdir("npm-release") do |folder|
      limited(npm + ["pack", "#{name}@#{version}", "--pack-destination", folder, "--loglevel=error", "--ignore-scripts"], FETCH_SECONDS)
      tarball = Dir.glob("*.tgz", base: folder).first or raise Failure, "npm pack #{name}@#{version} wrote no package"
      path = File.join(folder, tarball)
      check_integrity(release, path)
      texts(path, name, version)
    end
  end

  # Fails unless the tarball at +path+ has the integrity that +release+
  # lists, naming the work, the version, and both values.
  def check_integrity(release, path)
    got = "sha512-#{Digest::SHA512.file(path).base64digest}"
    return if got == release.integrity

    raise Failure, "#{release.work} #{release.version}: the tarball that npm pack #{release.package}@#{release.version} fetched has the integrity #{got}, " \
      "and tasks/bundled_works.rb lists #{release.integrity || 'none'} for it. " \
      "If #{release.version} is a new version, look at what its tarball ships, and then list its integrity in the table."
  end

  # Runs +command+, and stops it when it takes more than +seconds+.
  def limited(command, seconds)
    Open3.popen3(*command) do |stdin, stdout, stderr, thread|
      stdin.close
      readers = [stdout, stderr].map { |io| Thread.new { io.read } }
      unless thread.join(seconds)
        Process.kill("KILL", thread.pid)
        thread.join
        raise Failure, "#{command.join(' ')} took more than #{seconds} seconds"
      end
      raise Failure, "#{command.join(' ')} failed:\n#{readers.last.value}" unless thread.value.success?
    end
  end

  # The files at the top of the package in the tarball +path+ that
  # RELEASE_TEXT matches, without unpacking anything to a disk.
  def texts(path, name, version)
    found = {}
    Zlib::GzipReader.open(path) do |gzip|
      Gem::Package::TarReader.new(gzip).each do |entry|
        file = entry.full_name.delete_prefix("package/")
        found[file] = entry.read.force_encoding("UTF-8").scrub if entry.file? && !file.include?("/") && file.match?(RELEASE_TEXT)
      end
    end
    raise Failure, "#{name}@#{version} has no license file" unless found.keys.any? { |file| file.match?(/\Alicen[cs]e/i) }

    found.sort.to_h
  end
end
