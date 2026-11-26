# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Spike: parse TypeScript and TSX with ruby_tree_sitter, print each class and
# its decorated members, then load the Ruby rule files of a project.
#
#   tsspike [--info] [--rules DIR] FILE.ts|FILE.tsx...

require "rbconfig"
require "tree_sitter"

module TsSpike
  GRAMMARS = File.join(__dir__, "parsers")
  EXT = case RbConfig::CONFIG["host_os"]
        when /darwin/ then "dylib"
        when /mingw|mswin/ then "dll"
        else "so"
        end

  @rules = []
  class << self
    attr_reader :rules

    # What a project's rule file calls to register a rule.
    def rule(name, &check) = @rules << [name, check]

    def language(name)
      @languages ||= {}
      @languages[name] ||= TreeSitter::Language.load(
        name, File.join(GRAMMARS, "libtree-sitter-#{name}.#{EXT}")
      )
    end
  end

  # Facts about one file: its classes, and the members that carry a decorator.
  def self.facts(path)
    grammar = path.end_with?(".tsx") ? "tsx" : "typescript"
    parser = TreeSitter::Parser.new
    parser.language = language(grammar)
    src = File.read(path)
    root = parser.parse_string(nil, src).root_node
    classes = []
    walk(root) do |node|
      next unless %w[class_declaration abstract_class_declaration class].include?(node.type.to_s) && node.named?

      classes << class_facts(node, src)
    end
    { path: path, classes: classes }
  end

  def self.walk(node, &block)
    block.call(node)
    node.each { |child| walk(child, &block) }
  end

  def self.text(node, src) = src.byteslice(node.start_byte, node.end_byte - node.start_byte)

  def self.class_facts(node, src)
    name = node.each.find { |c| c.type.to_s == "type_identifier" }
    body = node.each.find { |c| c.type.to_s == "class_body" }
    # A class's own decorators are children of the class node. A member's
    # decorators sit in the body, as siblings before the member.
    # An exported class has them on its export_statement instead.
    holders = [node]
    holders << node.parent if node.parent && node.parent.type.to_s == "export_statement"
    class_decorators = holders.flat_map { |h| h.each.select { |c| c.type.to_s == "decorator" } }.map { |d| text(d, src) }
    members = []
    pending = []
    body&.each do |child|
      case child.type.to_s
      when "decorator"
        pending << text(child, src)
      when "public_field_definition", "method_definition"
        own = child.each.select { |c| c.type.to_s == "decorator" }.map { |d| text(d, src) }
        decorators = pending + own
        pending = []
        member_name = child.each.find { |c| %w[property_identifier private_property_identifier].include?(c.type.to_s) }
        unless decorators.empty?
          members << { kind: child.type.to_s, name: member_name && text(member_name, src),
                       decorators: decorators }
        end
      else
        pending = []
      end
    end
    { name: name && text(name, src), decorators: class_decorators, members: members }
  end

  def self.report(facts)
    puts facts[:path]
    facts[:classes].each do |klass|
      puts "  class #{klass[:name]} #{klass[:decorators].join(" ")}".rstrip
      klass[:members].each do |m|
        puts "    #{m[:decorators].join(" ")} #{m[:name]} (#{m[:kind]})"
      end
    end
  end

  def self.info
    puts "ruby #{RUBY_VERSION} #{RUBY_PLATFORM}"
    puts "RbConfig.ruby #{RbConfig.ruby}"
    puts "program #{File.expand_path($PROGRAM_NAME)}"
    puts "grammars #{GRAMMARS} #{Dir.exist?(GRAMMARS) ? Dir.children(GRAMMARS).sort.join(",") : "missing"}"
    puts "cwd #{Dir.pwd}"
    puts "frozen_bundle #{defined?(Bundler) && Bundler.frozen_bundle?}"
  end

  # Load every .rb file in DIR and say what happened to each. A LoadError is
  # reported and the next file still loads.
  def self.load_rules(dir)
    Dir.glob(File.join(dir, "*.rb")).sort.each do |file|
      before = rules.size
      begin
        load(file)
        puts "rule file #{File.basename(file)}: loaded, #{rules.size - before} rule(s)"
      rescue LoadError, StandardError, ScriptError => e
        puts "rule file #{File.basename(file)}: #{e.class}: #{e.message.lines.first&.strip}"
      end
    end
  end

  def self.run_rules(all_facts)
    rules.each do |name, check|
      all_facts.each do |facts|
        Array(check.call(facts)).each { |message| puts "#{name}: #{facts[:path]}: #{message}" }
      end
    end
  end
end

args = ARGV.dup
rules_dir = nil
info = false
files = []
until args.empty?
  case (arg = args.shift)
  when "--info" then info = true
  when "--rules" then rules_dir = args.shift
  else files << arg
  end
end

TsSpike.info if info
all = files.map { |f| TsSpike.facts(f) }
all.each { |f| TsSpike.report(f) }
if rules_dir
  TsSpike.load_rules(rules_dir)
  TsSpike.run_rules(all)
end
