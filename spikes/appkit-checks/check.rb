#!/usr/bin/env ruby
# frozen_string_literal: true

# Spike: the two AppKit checks, from Ruby.
#
#   ruby check.rb [--verify] [--tests] [ROOT]
#
# ROOT is an AppKit app (default: fixture/). Prints, for each query file, whether
# a use of its key was found, and for each bundle file whether it grants `sql`.
# --verify compares the result with ROOT/expected.yml and exits 1 on a mismatch.
# --tests counts files named *.test.* as uses.

require "json"
require "yaml"
require "tree_sitter"

HERE = File.expand_path(__dir__)
EXT = RbConfig::CONFIG["host_os"].match?(/darwin/) ? "dylib" : "so"
APPKIT_UI = %r{\A@databricks/appkit-ui}
KEY_PATTERN = /\A[a-zA-Z0-9_-]+\z/ # packages/appkit/src/app/index.ts, getAppQuery

# ---------------------------------------------------------------- TypeScript

class TsFile
  attr_reader :path, :src, :root, :consts, :imports, :exports, :star_exports

  def initialize(path, language)
    @path = path
    @src = File.read(path)
    parser = TreeSitter::Parser.new
    parser.language = language
    @language = language
    @root = parser.parse_string(nil, @src).root_node
    @consts = {}       # local const name => String | Hash | nil (not a literal)
    @imports = {}      # local name => [source, imported name or :namespace]
    @exports = {}      # exported name => [source, name] for `export { x } from`
    @star_exports = [] # sources of `export * from`
    index
  end

  def text(node) = @src.byteslice(node.start_byte, node.end_byte - node.start_byte)

  def line(node) = node.start_point.row + 1

  def named(node) = node.each_named.to_a

  # The literal value of a string node, or nil when it has a substitution.
  def string_value(node)
    case node.type.to_s
    when "string"
      named(node).select { |c| c.type.to_s == "string_fragment" }.map { |c| text(c) }.join
    when "template_string"
      return nil if named(node).any? { |c| c.type.to_s == "template_substitution" }

      named(node).map { |c| text(c) }.join
    end
  end

  # A value a const can hold that we can read without running anything.
  def literal(node)
    node = unwrap(node)
    case node.type.to_s
    when "string", "template_string" then string_value(node)
    when "object"
      named(node).select { |c| c.type.to_s == "pair" }.to_h do |pair|
        [text(pair.child_by_field_name("key")).delete("\"'"), literal(pair.child_by_field_name("value"))]
      end
    end
  end

  # Look through `x as const`, `x satisfies T`, `(x)`, and `x!`.
  def unwrap(node)
    while %w[as_expression satisfies_expression parenthesized_expression non_null_expression].include?(node.type.to_s)
      node = named(node).first
    end
    node
  end

  private

  def index
    named(@root).each do |top|
      case top.type.to_s
      when "import_statement" then index_import(top)
      when "lexical_declaration" then index_const(top)
      when "export_statement" then index_export(top)
      end
    end
  end

  def index_import(node)
    source = string_value(node.child_by_field_name("source"))
    clause = named(node).find { |c| c.type.to_s == "import_clause" } or return
    named(clause).each do |part|
      case part.type.to_s
      when "named_imports"
        named(part).each do |spec|
          name = text(spec.child_by_field_name("name"))
          alias_node = spec.child_by_field_name("alias")
          @imports[alias_node ? text(alias_node) : name] = [source, name]
        end
      when "namespace_import"
        @imports[text(named(part).first)] = [source, :namespace]
      end
    end
  end

  def index_const(node)
    named(node).each do |decl|
      next unless decl.type.to_s == "variable_declarator"

      name = decl.child_by_field_name("name")
      value = decl.child_by_field_name("value")
      @consts[text(name)] = literal(value) if name.type.to_s == "identifier" && value
    end
  end

  def index_export(node)
    source_node = node.child_by_field_name("source")
    decl = node.child_by_field_name("declaration")
    if decl&.type.to_s == "lexical_declaration"
      index_const(decl)
    elsif source_node
      source = string_value(source_node)
      clause = named(node).find { |c| c.type.to_s == "export_clause" }
      if clause
        named(clause).each do |spec|
          name = text(spec.child_by_field_name("name"))
          alias_node = spec.child_by_field_name("alias")
          @exports[alias_node ? text(alias_node) : name] = [source, name]
        end
      else
        @star_exports << source
      end
    end
  end
end

# What a key expression resolves to: literal keys, or a reason it cannot be read.
Resolution = Struct.new(:keys, :why)

class Project
  attr_reader :root, :files, :language_for

  def initialize(root, languages, include_tests:)
    @root = root
    @languages = languages
    @files = {}
    @alias = read_aliases
    paths = Dir.glob(File.join(root, "{client,server,shared,src}/**/*.{ts,tsx}"))
    paths.reject! { |p| p.match?(%r{/(node_modules|dist)/}) || p.end_with?(".d.ts") }
    paths.reject! { |p| p.match?(/\.(test|spec)\.tsx?\z/) } unless include_tests
    paths.sort.each do |path|
      language = path.end_with?(".tsx") ? languages[:tsx] : languages[:typescript]
      @files[path] = TsFile.new(path, language)
    end
  end

  def rel(path) = path.delete_prefix("#{@root}/")

  # tsconfig "paths": {"@/*": ["./client/src/*"]} as [prefix, dir] pairs.
  def read_aliases
    %w[tsconfig.client.json tsconfig.json].each do |name|
      file = File.join(@root, name)
      next unless File.exist?(file)

      json = JSON.parse(File.read(file).gsub(%r{^\s*//.*$}, ""))
      paths = json.dig("compilerOptions", "paths") || {}
      return paths.map { |pattern, targets| [pattern.delete_suffix("*"), File.join(@root, targets.first.delete_suffix("*"))] }
    end
    []
  end

  def locate(from, source)
    base =
      if source.start_with?(".")
        File.expand_path(source, File.dirname(from))
      elsif (prefix, dir = @alias.find { |pre, _| source.start_with?(pre) })
        File.expand_path(source.delete_prefix(prefix), dir)
      end
    return unless base

    ["", ".ts", ".tsx", "/index.ts", "/index.tsx"].map { |suffix| base + suffix }.find { |p| @files.key?(p) }
  end

  # Finds exported const `name` in the file at `path`, following `export ... from`.
  def exported_const(path, name, seen = [])
    return [nil, "cycle"] if seen.include?(path)

    file = @files[path]
    return [file.consts[name], nil] if file.consts.key?(name)

    if (source, original = file.exports[name])
      target = locate(path, source) or return [nil, "cannot locate #{source}"]
      return exported_const(target, original, seen + [path])
    end
    file.star_exports.each do |source|
      target = locate(path, source) or next
      value, = exported_const(target, name, seen + [path])
      return [value, nil] unless value.nil?
    end
    [nil, "no const #{name} in #{rel(path)}"]
  end

  def resolve(file, node)
    node = file.unwrap(node)
    case node.type.to_s
    when "string", "template_string"
      value = file.string_value(node)
      value ? Resolution.new([value], nil) : Resolution.new([], "template literal with a substitution")
    when "identifier"
      resolve_name(file, file.text(node))
    when "member_expression"
      object = file.unwrap(node.child_by_field_name("object"))
      prop = file.text(node.child_by_field_name("property"))
      return Resolution.new([], "member of #{object.type}") unless object.type.to_s == "identifier"

      table = resolve_value(file, file.text(object))
      table.is_a?(Hash) && table[prop].is_a?(String) ? Resolution.new([table[prop]], nil) : Resolution.new([], "cannot read #{file.text(node)}")
    when "ternary_expression"
      arms = %w[consequence alternative].map { |f| resolve(file, node.child_by_field_name(f)) }
      Resolution.new(arms.flat_map(&:keys), arms.filter_map(&:why).first)
    else
      Resolution.new([], "#{node.type} expression")
    end
  end

  def resolve_name(file, name)
    value = resolve_value(file, name)
    return Resolution.new([value], nil) if value.is_a?(String)

    Resolution.new([], "#{name} is not a string constant")
  end

  def resolve_value(file, name)
    return file.consts[name] if file.consts.key?(name)

    source, imported = file.imports[name]
    return nil unless source

    target = locate(file.path, source) or return nil
    exported_const(target, imported)[0]
  end
end

# A place a key reaches AppKit.
Use = Struct.new(:file, :line, :how, :keys, :why)

class UseFinder
  CHART_HOOKS = %w[useChartData].freeze

  def initialize(project, languages)
    @project = project
    @queries = languages.to_h do |key, language|
      queries = { call: TreeSitter::Query.new(language, "(call_expression function: (_) @fn arguments: (arguments . (_) @first)) @call") }
      # The TypeScript grammar has no JSX nodes; only the TSX grammar can ask for them.
      if key == :tsx
        queries[:attr] = TreeSitter::Query.new(language, "(jsx_attribute (property_identifier) @name (_) @value) @attr")
      end
      [key, queries]
    end
  end

  def uses
    @project.files.values.flat_map { |file| uses_in(file) }
  end

  # Every string literal in the file that is not a comment (tree-sitter knows comments from code).
  def literals(file)
    out = []
    walk = lambda do |node|
      case node.type.to_s
      when "string", "template_string"
        value = file.string_value(node)
        out << value if value
      end
      node.each_named { |child| walk.call(child) }
    end
    walk.call(file.root)
    out
  end

  private

  def run(file, name)
    key = file.path.end_with?(".tsx") ? :tsx : :typescript
    cursor = TreeSitter::QueryCursor.new
    cursor.matches(@queries[key][name], file.root, file.src).each_capture_hash.to_a
  end

  def uses_in(file)
    found = []
    run(file, :call).each do |m|
      kind = hook_kind(file, m["fn"]) or next
      arg = m["first"]
      if kind == :analytics
        found << use(file, m["call"], "useAnalyticsQuery(...)", arg)
      elsif arg.type.to_s == "object"
        file.named(arg).each do |pair|
          next unless pair.type.to_s == "pair" && file.text(pair.child_by_field_name("key")) == "queryKey"

          found << use(file, pair, "useChartData({queryKey})", pair.child_by_field_name("value"))
        end
      end
    end
    (file.path.end_with?(".tsx") ? run(file, :attr) : []).each do |m|
      next unless file.text(m["name"]) == "queryKey"

      value = m["value"]
      value = file.named(value).first if value.type.to_s == "jsx_expression"
      element = m["attr"].parent
      tag = file.text(element.child_by_field_name("name") || file.named(element).first)
      found << use(file, m["attr"], "<#{tag} queryKey>", value)
    end
    found
  end

  # :analytics for useAnalyticsQuery, :chart for useChartData, nil otherwise.
  # The callee must be imported from AppKit's UI package, directly or by namespace.
  def hook_kind(file, fn)
    name =
      if fn.type.to_s == "identifier"
        local = file.text(fn)
        source, imported = file.imports[local]
        imported if source&.match?(APPKIT_UI)
      elsif fn.type.to_s == "member_expression"
        object = file.text(fn.child_by_field_name("object"))
        source, imported = file.imports[object]
        file.text(fn.child_by_field_name("property")) if source&.match?(APPKIT_UI) && imported == :namespace
      end
    return :analytics if name == "useAnalyticsQuery"
    :chart if CHART_HOOKS.include?(name)
  end

  def use(file, node, how, value_node)
    resolution = @project.resolve(file, value_node)
    Use.new(@project.rel(file.path), file.line(node), how, resolution.keys, resolution.why)
  end
end

# ------------------------------------------------------------ query files

QueryFile = Struct.new(:path, :key, :lane, :problem)

def query_files(root)
  Dir.glob(File.join(root, "config/queries/**/*.sql")).sort.map do |path|
    rel = path.delete_prefix("#{root}/")
    base = File.basename(path, ".sql")
    lane = base.end_with?(".obo") ? :obo : :service_principal
    key = base.delete_suffix(".obo")
    problem =
      if File.dirname(rel) != "config/queries" then "in a subfolder: AppKit reads only the top level"
      elsif !KEY_PATTERN.match?(key) then "key does not match #{KEY_PATTERN.source}"
      end
    QueryFile.new(rel, key, lane, problem)
  end
end

def check_query_keys(root, languages, include_tests:)
  project = Project.new(root, languages, include_tests: include_tests)
  finder = UseFinder.new(project, languages)
  uses = finder.uses
  literals = project.files.values.to_h { |f| [f.path, finder.literals(f)] }
  used_keys = uses.flat_map(&:keys).uniq
  loose_keys = literals.values.flatten.uniq
  dynamic = uses.select(&:why)
  queries = query_files(root)
  both = queries.group_by(&:key).select { |_, v| v.size > 1 }.keys

  rows = queries.map do |q|
    status = if used_keys.include?(q.key) then :used
             elsif loose_keys.include?(q.key) then :loose
             else :unused
             end
    status = :unreachable if q.problem
    [q, status]
  end
  [rows, dynamic, both, uses]
end

# --------------------------------------------------------------- databricks.yml

SQL_SCOPES = %w[sql].freeze
# Deprecated names the docs map to `sql`.
SQL_ALIASES = %w[sql.alerts sql.alerts-legacy sql.dashboards sql.data-sources sql.dbsql-permissions sql.queries
                 sql.queries-legacy sql.query-history sql.statement-execution sql.warehouses].freeze
SQL_NARROW = %w[sql:read sql:restricted-query].freeze

# All user_api_scopes in a bundle file and the files it includes, as {where => [scopes]}.
def bundle_scopes(path, seen = [])
  return {} if seen.include?(path)

  doc = YAML.safe_load_file(path) || {}
  found = {}
  apps = ->(tree, where) do
    (tree.dig("resources", "apps") || {}).each do |name, app|
      scopes = app.is_a?(Hash) ? app["user_api_scopes"] : nil
      found["#{where}apps.#{name}"] = Array(scopes) unless scopes.nil?
      found["#{where}apps.#{name}"] ||= [] if app.is_a?(Hash)
    end
  end
  apps.call(doc, "")
  (doc["targets"] || {}).each { |target, tree| apps.call(tree, "targets.#{target}.") if tree.is_a?(Hash) }
  Array(doc["include"]).each do |pattern|
    Dir.glob(File.join(File.dirname(path), pattern)).sort.each do |inc|
      bundle_scopes(inc, seen + [path]).each { |where, scopes| found["#{File.basename(inc)}:#{where}"] = scopes }
    end
  end
  found
end

def sql_verdict(scopes_by_app)
  all = scopes_by_app.values.flatten.map(&:to_s)
  if all.any? { |s| SQL_SCOPES.include?(s) } then :ok
  elsif all.any? { |s| SQL_ALIASES.include?(s) } then :ok_deprecated_name
  elsif all.any? { |s| SQL_NARROW.include?(s) } then :narrow_scope_needs_review
  else :missing
  end
end

def check_obo_scope(root)
  dir = File.join(root, "bundles")
  Dir.glob(File.join(dir, "*.yml")).sort.map do |path|
    scopes = bundle_scopes(path)
    [File.basename(path), sql_verdict(scopes), scopes]
  end
end

# ----------------------------------------------------------------------- main

def load_languages
  build = File.join(HERE, "build")
  {
    typescript: TreeSitter::Language.load("typescript", File.join(build, "libtree-sitter-typescript.#{EXT}")),
    tsx: TreeSitter::Language.load("tsx", File.join(build, "libtree-sitter-tsx.#{EXT}"))
  }
end

def naive_grep(root, key)
  Dir.glob(File.join(root, "{client,shared,server}/**/*")).select { |p| File.file?(p) }.count { |p| File.read(p).include?(key) }
end

args = ARGV.dup
verify = args.delete("--verify")
include_tests = args.delete("--tests")
root = File.expand_path(args.first || File.join(HERE, "fixture"))

languages = load_languages
rows, dynamic, both, = check_query_keys(root, languages, include_tests: include_tests)

puts "== Check 1: every config/queries key reaches a hook or component"
rows.each do |q, status|
  note = q.problem ? "  (#{q.problem})" : ""
  note += "  (also has a .sql twin: .obo.sql wins)" if both.include?(q.key) && !q.problem
  puts format("  %-26s %-8s %-18s text-search files: %d%s", q.key, q.lane == :obo ? "obo" : "sp", status, naive_grep(root, q.key), note)
end
puts "  call sites whose key syntax cannot read (an unused key may be used here):"
dynamic.each { |u| puts "    #{u.file}:#{u.line} #{u.how}: #{u.why}" }

puts "== Check 2: *.obo.sql needs the sql scope in databricks.yml"
obo = query_files(root).select { |q| q.lane == :obo }.map(&:path)
puts "  obo query files: #{obo.empty? ? "none (check does not apply)" : obo.join(", ")}"
bundles = check_obo_scope(root)
bundles.each { |name, verdict, scopes| puts format("  %-24s %-28s %s", name, verdict, scopes.inspect) }

if verify
  expected = YAML.safe_load_file(File.join(root, "expected.yml"))
  actual = {
    "queries" => rows.to_h { |q, s| [q.path.delete_prefix("config/queries/"), s.to_s] },
    "bundles" => bundles.to_h { |name, verdict, _| [name, verdict.to_s] }
  }
  bad = %w[queries bundles].flat_map do |part|
    (expected[part].keys | actual[part].keys).filter_map do |k|
      "#{part}/#{k}: expected #{expected[part][k].inspect}, got #{actual[part][k].inspect}" if expected[part][k] != actual[part][k]
    end
  end
  if bad.empty?
    puts "VERIFIED: #{actual["queries"].size} query files and #{actual["bundles"].size} bundles match expected.yml"
  else
    puts "MISMATCH:", bad.map { |b| "  #{b}" }
    exit 1
  end
end
