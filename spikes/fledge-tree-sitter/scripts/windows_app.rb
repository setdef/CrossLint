# frozen_string_literal: true

# Windows only. Copies app/ to build/app-windows/ and swaps its ruby_tree_sitter
# for a copy of 2.1.1 with the two changes its C needs to compile and run on
# 64-bit Windows:
#
# - logger.c names a local variable `stderr`, which Windows' C library defines
#   as a macro, so the line does not compile.
# - tree.c keeps a pointer in an unsigned long (ULONG2NUM, NUM2ULONG), which
#   is 32 bits on Windows, so the pointer is cut in half.
#
#   ruby scripts/windows_app.rb

require "fileutils"
require "tmpdir"

root = File.expand_path("..", __dir__)
dest = File.join(root, "build", "app-windows")
vendor = File.join(dest, "vendor")
FileUtils.rm_rf(dest)
FileUtils.cp_r(File.join(root, "app"), dest)
FileUtils.rm_f(File.join(dest, "Gemfile.lock"))
FileUtils.mkdir_p(vendor)

Dir.mktmpdir do |tmp|
  system("gem", "fetch", "ruby_tree_sitter", "-v", "2.1.1", "--platform", "ruby", chdir: tmp) || abort("gem fetch failed")
  system("gem", "unpack", File.join(tmp, "ruby_tree_sitter-2.1.1.gem"), "--target", vendor) || abort("gem unpack failed")
end

gem_dir = File.join(vendor, "ruby_tree_sitter-2.1.1")
ext = File.join(gem_dir, "ext", "tree_sitter")

def patch(path, from, to)
  text = File.read(path)
  abort "#{path}: #{from.inspect} not found" unless text.include?(from)
  File.write(path, text.gsub(from, to))
end

patch(File.join(ext, "logger.c"), "VALUE stderr = rb_gv_get", "VALUE err_io = rb_gv_get")
patch(File.join(ext, "logger.c"), "if (!NIL_P(stderr))", "if (!NIL_P(err_io))")
patch(File.join(ext, "logger.c"), "logger_payload_set(logger, stderr);", "logger_payload_set(logger, err_io);")
patch(File.join(ext, "tree.c"), "ULONG2NUM", "ULL2NUM")
patch(File.join(ext, "tree.c"), "NUM2ULONG", "NUM2ULL")

File.write(File.join(dest, "Gemfile"), <<~GEMFILE)
  # frozen_string_literal: true

  source "https://rubygems.org"

  gem "ruby_tree_sitter", path: "vendor/ruby_tree_sitter-2.1.1"
GEMFILE

Dir.chdir(dest) do
  system("bundle", "lock", "--add-platform", "x64-mingw-ucrt") || abort("bundle lock failed")
end
puts dest
