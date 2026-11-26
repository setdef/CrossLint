# frozen_string_literal: true


# Builds ruby_tree_sitter 2.1.1 from its source gem, tree-sitter 0.26.5 and
# the JSON grammar for the Ruby that runs this script, into build/NAME/.
# No Bundler and no Fledge: the extension is compiled with mkmf and loaded
# with `ruby -I build/NAME/gem/lib`.
#
#   ruby build.rb NAME [--ulong] [--fix]
#
# NAME      the folder under build/ for this variant.
# --ulong   Windows only: keep tree.c's ULONG2NUM and NUM2ULONG, which cut a
#           pointer to 32 bits there. Without it, Windows builds use
#           ULL2NUM and NUM2ULL.
# --fix     the patch in patches/free-deferred.patch.
#
# On Windows the gem needs three changes before it compiles at all (logger.c's
# local variable `stderr` is a macro there, language.c includes dlfcn.h, and
# tree.c keeps a pointer in an unsigned long); they are made here and are
# the same as scripts/windows_app.rb in ../fledge-tree-sitter.

require "digest"
require "fileutils"
require "net/http"
require "rbconfig"
require "rubygems/package"
require "stringio"
require "zlib"

CORE_VERSION = "0.26.5"
CORE_SHA256 = "8e012493b2103e0471d3aba8048b73bc1a3138132974e2fd8bfb89a63e62f478"
JSON_VERSION = "0.24.8"
JSON_SHA256 = "acf6e8362457e819ed8b613f2ad9a0e1b621a77556c296f3abea58f7880a9213"
GEM_VERSION = "2.1.1"

here = __dir__
args = ARGV.dup
name = args.shift or abort "usage: ruby build.rb NAME [--ulong] [--fix]"
ulong = args.delete("--ulong")
fix = args.delete("--fix")
abort "unknown arguments: #{args.join(" ")}" unless args.empty?

windows = RbConfig::CONFIG["host_os"].match?(/mingw|mswin/)
darwin = RbConfig::CONFIG["host_os"].match?(/darwin/)
shared_ext = windows ? "dll" : (darwin ? "dylib" : "so")
cc = ENV.fetch("CC", RbConfig::CONFIG["CC"].to_s.split.first || "cc")

cache = File.join(here, "build", "downloads")
out = File.join(here, "build", name)
FileUtils.rm_rf(out)
FileUtils.mkdir_p([cache, out])

def run(*cmd, **opts)
  puts "+ #{cmd.join(" ")}"
  system(*cmd, **opts) || abort("failed: #{cmd.join(" ")}")
end

def fetch(url, limit = 5)
  raise "too many redirects" if limit.zero?

  res = Net::HTTP.get_response(URI(url))
  case res
  when Net::HTTPRedirection then fetch(res["location"], limit - 1)
  when Net::HTTPSuccess then res.body
  else raise "#{url}: #{res.code}"
  end
end

# Downloads URL (once), checks its SHA-256, unpacks it under DIR, returns the top folder.
def source(url, sha256, cache, dir)
  file = File.join(cache, File.basename(url).then { |b| "#{sha256[0, 8]}-#{b}" })
  File.binwrite(file, fetch(url)) unless File.exist?(file)
  actual = Digest::SHA256.file(file).hexdigest
  abort "#{url}: SHA-256 #{actual}, expected #{sha256}" unless actual == sha256
  FileUtils.rm_rf(dir)
  FileUtils.mkdir_p(dir)
  Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(File.binread(file)))).each do |entry|
    path = File.join(dir, entry.full_name)
    if entry.directory?
      FileUtils.mkdir_p(path)
    elsif entry.file?
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, entry.read)
    end
  end
  Dir.children(dir).first.then { |top| File.join(dir, top) }
end

def patch(path, from, to)
  text = File.binread(path)
  abort "#{path}: #{from.inspect} not found" unless text.include?(from)
  File.binwrite(path, text.gsub(from, to))
end

# tree-sitter's library, as a static archive the extension links in.
core = source("https://github.com/tree-sitter/tree-sitter/archive/refs/tags/v#{CORE_VERSION}.tar.gz",
              CORE_SHA256, cache, File.join(out, "src-core"))
inc = File.join(out, "include")
lib = File.join(out, "lib")
FileUtils.mkdir_p([File.join(inc, "tree_sitter"), lib])
FileUtils.cp(File.join(core, "lib", "include", "tree_sitter", "api.h"), File.join(inc, "tree_sitter"))
FileUtils.cp(File.join(here, "dlfcn.h"), inc) if windows
cflags = %w[-c -O2 -std=c11 -D_POSIX_C_SOURCE=200112L -D_DEFAULT_SOURCE]
cflags << "-fPIC" unless windows
run cc, *cflags, "-I", File.join(core, "lib", "src"), "-I", File.join(core, "lib", "include"),
    File.join(core, "lib", "src", "lib.c"), "-o", File.join(out, "lib.o")
run "ar", "rcs", File.join(lib, "libtree-sitter.a"), File.join(out, "lib.o")

# The JSON grammar, as a shared library that exports tree_sitter_json.
json = source("https://github.com/tree-sitter/tree-sitter-json/archive/refs/tags/v#{JSON_VERSION}.tar.gz",
              JSON_SHA256, cache, File.join(out, "src-json"))
flags = darwin ? %w[-dynamiclib] : (windows ? %w[-shared] : %w[-shared -fPIC])
run cc, *flags, "-O2", "-I", File.join(json, "src"), "-o", File.join(out, "libtree-sitter-json.#{shared_ext}"),
    File.join(json, "src", "parser.c")

# The gem.
gems = File.join(out, "src-gem")
FileUtils.mkdir_p(gems)
run "gem", "fetch", "ruby_tree_sitter", "-v", GEM_VERSION, "--platform", "ruby", chdir: gems
run "gem", "unpack", File.join(gems, "ruby_tree_sitter-#{GEM_VERSION}.gem"), "--target", gems
gem_dir = File.join(out, "gem")
FileUtils.mv(File.join(gems, "ruby_tree_sitter-#{GEM_VERSION}"), gem_dir)
ext = File.join(gem_dir, "ext", "tree_sitter")

if windows
  patch(File.join(ext, "logger.c"), "VALUE stderr = rb_gv_get", "VALUE err_io = rb_gv_get")
  patch(File.join(ext, "logger.c"), "if (!NIL_P(stderr))", "if (!NIL_P(err_io))")
  patch(File.join(ext, "logger.c"), "logger_payload_set(logger, stderr);", "logger_payload_set(logger, err_io);")
  unless ulong
    patch(File.join(ext, "tree.c"), "ULONG2NUM", "ULL2NUM")
    patch(File.join(ext, "tree.c"), "NUM2ULONG", "NUM2ULL")
  end
end

if fix
  patch_file = File.join(here, "patches", "free-deferred.patch")
  run "patch", "-p1", "-d", gem_dir, "-i", patch_file
end

Dir.chdir(ext) do
  run RbConfig.ruby, "extconf.rb", "--enable-sys-libs",
      "--with-tree-sitter-include=#{inc.tr("\\", "/")}", "--with-tree-sitter-lib=#{lib.tr("\\", "/")}"
  run "make"
end
FileUtils.mkdir_p(File.join(gem_dir, "lib", "tree_sitter"))
built = Dir.glob(File.join(ext, "tree_sitter.#{RbConfig::CONFIG["DLEXT"]}")).first or abort "no extension built"
FileUtils.cp(built, File.join(gem_dir, "lib", "tree_sitter"))
puts "built #{out}"
