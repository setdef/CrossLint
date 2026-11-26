# frozen_string_literal: true


# The smallest program that frees a ruby_tree_sitter tree.
#
#   ruby -I build/NAME/gem/lib repro.rb build/NAME/libtree-sitter-json.EXT MODE
#
# MODE is "exit" (parse, drop the tree, and let the process exit; the default),
# "gc" (parse, drop the tree, run GC.start, print, and exit with exit! so that
# no exit-time free runs), "keep" (keep the tree and exit with exit!, which
# frees nothing) or "many" (parse 3000 trees while the program runs, collect,
# and exit normally).

require "tree_sitter"

grammar = File.expand_path(ARGV.fetch(0))
mode = ARGV.fetch(1, "exit")

puts "ruby #{RUBY_DESCRIPTION}"
# A fixnum is the same object each time; a bignum is a new object (an allocation).
fixnum_bits = [20, 30, 31, 32, 40, 48, 61, 62].select { |bits| (1 << bits).equal?(1 << bits) }
puts "1 << bits is a fixnum for bits in #{fixnum_bits.inspect}"
parser = TreeSitter::Parser.new
parser.language = TreeSitter::Language.load("json", grammar)
tree = parser.parse_string(nil, '{"a": [1, 2]}')
puts "parsed: #{tree.root_node.type}"
$stdout.flush

case mode
when "exit"
  # Nothing more: the tree and its nodes are freed when Ruby exits.
when "gc"
  tree = nil
  GC.start
  puts "collected"
  $stdout.flush
  exit!(0)
when "keep"
  exit!(0)
when "many"
  # Thousands of trees and nodes, collected while the program runs, then a
  # normal exit.
  source = '{"a": [1, 2, {"b": null}], "c": "d"}'
  count = 0
  3000.times do
    root = parser.parse_string(nil, source).root_node
    root.each { |child| count += 1 if child.type }
  end
  GC.start
  puts "walked #{count} children of 3000 trees"
else
  abort "unknown mode #{mode}"
end
