# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Compile the TypeScript and TSX grammars into app/parsers/ for the computer
# this runs on. The source is tree-sitter-typescript's tagged release, checked
# against a SHA-256. Needs a C compiler. Run with any Ruby:
#
#   ruby scripts/grammars.rb

require "digest"
require "fileutils"
require "net/http"
require "rbconfig"
require "rubygems/package"
require "stringio"
require "tmpdir"
require "zlib"

VERSION = "0.23.2"
SHA256 = "2c4ce711ae8d1218a3b2f899189298159d672870b5b34dff5d937bed2f3e8983"
URL = "https://github.com/tree-sitter/tree-sitter-typescript/archive/refs/tags/v#{VERSION}.tar.gz"

root = File.expand_path("..", __dir__)
out = File.join(root, "app", "parsers")
work = File.join(ENV.fetch("TMPDIR", Dir.tmpdir), "tsspike-grammars")
FileUtils.rm_rf(work)
FileUtils.mkdir_p([work, out])

def fetch(url, limit = 5)
  raise "too many redirects" if limit.zero?

  res = Net::HTTP.get_response(URI(url))
  case res
  when Net::HTTPRedirection then fetch(res["location"], limit - 1)
  when Net::HTTPSuccess then res.body
  else raise "#{url}: #{res.code}"
  end
end

archive = fetch(URL)
actual = Digest::SHA256.hexdigest(archive)
abort "SHA-256 mismatch: #{actual}" unless actual == SHA256

Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(archive))).each do |entry|
  path = File.join(work, entry.full_name)
  if entry.directory?
    FileUtils.mkdir_p(path)
  elsif entry.file?
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, entry.read)
  end
end

src = File.join(work, "tree-sitter-typescript-#{VERSION}")
host = RbConfig::CONFIG["host_os"]
ext, flags =
  case host
  when /darwin/ then ["dylib", %w[-dynamiclib]]
  when /mingw|mswin/ then ["dll", %w[-shared]]
  else ["so", %w[-shared -fPIC]]
  end
cc = ENV.fetch("CC", "cc")

%w[typescript tsx].each do |name|
  dir = File.join(src, name, "src")
  target = File.join(out, "libtree-sitter-#{name}.#{ext}")
  cmd = [cc, *flags, "-O2", "-I", dir, "-o", target,
         File.join(dir, "parser.c"), File.join(dir, "scanner.c")]
  system(*cmd) || abort("compile failed: #{cmd.join(" ")}")
  puts "#{target} #{File.size(target)} bytes"
end
