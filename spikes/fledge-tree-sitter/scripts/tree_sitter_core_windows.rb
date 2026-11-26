# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Windows only. ruby_tree_sitter 2.1.1 cannot build its own copy of
# tree-sitter there (its extconf.rb shells out to Unix commands) and has no
# dlfcn.h to load a grammar with. This builds libtree-sitter.a from the
# tagged release, and puts it beside the library's headers and a dlfcn.h over
# LoadLibrary, in app/../build/tree-sitter-core/. It prints the value for
# BUNDLE_BUILD__RUBY_TREE_SITTER that makes the gem use them.
#
#   ruby scripts/tree_sitter_core_windows.rb

require "digest"
require "fileutils"
require "net/http"
require "rubygems/package"
require "stringio"
require "tmpdir"
require "zlib"

VERSION = "0.26.5"
SHA256 = "8e012493b2103e0471d3aba8048b73bc1a3138132974e2fd8bfb89a63e62f478"
URL = "https://github.com/tree-sitter/tree-sitter/archive/refs/tags/v#{VERSION}.tar.gz"

root = File.expand_path("..", __dir__)
out = File.join(root, "build", "tree-sitter-core")
work = File.join(Dir.tmpdir, "tsspike-core")
FileUtils.rm_rf([work, out])
FileUtils.mkdir_p([work, File.join(out, "include", "tree_sitter"), File.join(out, "lib")])

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

src = File.join(work, "tree-sitter-#{VERSION}", "lib")
cc = ENV.fetch("CC", "gcc")
obj = File.join(work, "lib.o")
compile = [cc, "-c", "-O2", "-std=c11", "-D_POSIX_C_SOURCE=200112L", "-D_DEFAULT_SOURCE",
           "-I", File.join(src, "src"), "-I", File.join(src, "include"),
           File.join(src, "src", "lib.c"), "-o", obj]
system(*compile) || abort("compile failed: #{compile.join(" ")}")
system("ar", "rcs", File.join(out, "lib", "libtree-sitter.a"), obj) || abort("ar failed")

FileUtils.cp(File.join(src, "include", "tree_sitter", "api.h"), File.join(out, "include", "tree_sitter"))
FileUtils.cp(File.join(__dir__, "windows", "dlfcn.h"), File.join(out, "include"))

dir = out.tr("\\", "/")
puts "--enable-sys-libs --with-tree-sitter-include=#{dir}/include --with-tree-sitter-lib=#{dir}/lib"
