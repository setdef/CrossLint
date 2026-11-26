# Approach A: read a component's inputs and outputs from Ruby with the
# ruby_tree_sitter gem and the tree-sitter TypeScript grammar. There is no
# type checker, so everything ts-morph does for ng-nudge when it follows a
# base class (read tsconfig, resolve the import, find the exported class) is
# written out here.
require "json"
require "pathname"
require "set"
require "tree_sitter"

module TsReader
  Api = Struct.new(:inputs, :outputs) # both: Array of names, in order found

  CLASS_TYPES = %i[class_declaration abstract_class_declaration].freeze
  EXTENSIONS = %w[.ts .tsx .d.ts].freeze

  # What tree-sitter gives: a tree per file. Nothing else.
  Source = Struct.new(:path, :text, :root) do
    def text_of(node) = text.byteslice(node.start_byte, node.end_byte - node.start_byte)
  end

  class Reader
    # strict: false mimics ng-nudge exactly. strict: true also reads the forms
    # ng-nudge misses (see the README).
    # mixin_heuristic: treat `extends mixin(Base)` as `extends Base`.
    def initialize(grammar:, project_root:, strict: false, mixin_heuristic: false)
      @parser = TreeSitter::Parser.new
      @parser.language = TreeSitter::Language.load("typescript", grammar)
      @root = File.expand_path(project_root)
      @strict = strict
      @mixin_heuristic = mixin_heuristic
      @sources = {}
      @tsconfig = load_tsconfig(File.join(@root, "tsconfig.json"))
    end

    # ---- the two things the rules ask for -------------------------------

    def component_api(path)
      src = source(path) or return nil
      classes = top_level_classes(src)
      return nil if classes.empty?
      cls = classes.find { |c| decorators(src, c[:holder]).include?("Component") } or return nil

      inputs = []
      outputs = []
      seen = Set.new
      current = [src, cls[:decl]]
      while current && seen.add?(current[1].start_byte.to_s + current[0].path)
        collect_members(*current, inputs, outputs)
        current = base_class(*current)
      end
      Api.new(inputs, outputs)
    end

    def interface_names(path)
      src = source(path) or return nil
      ifaces = src.root.each_named.flat_map do |n|
        n.type == :interface_declaration ? [n] : (n.type == :export_statement ? [n.child_by_field_name("declaration")].compact.select { |d| d.type == :interface_declaration } : [])
      end
      raise "Expected exactly 1 interface in #{path}, found #{ifaces.size}" unless ifaces.size == 1
      body = ifaces[0].child_by_field_name("body")
      body.each_named.select { |m| m.type == :property_signature }.map { |m| member_name(src, m) }
    end

    # ---- reading members -------------------------------------------------

    private

    def collect_members(src, cls, inputs, outputs)
      body = cls.child_by_field_name("body")
      pending = [] # tree-sitter puts a method's decorators before it, as siblings
      body.each_named do |m|
        case m.type
        when :decorator
          pending << decorator_name(src, m)
          next
        when :public_field_definition
          next if m.each.any? { |c| c.type == :static } && !(@strict && %w[ɵcmp ɵdir].include?(member_name(src, m)))
          collect_field(src, m, inputs, outputs)
        when :method_definition
          collect_accessor(src, m, pending, inputs, outputs) if @strict
        end
        pending = []
      end
    end

    def collect_field(src, field, inputs, outputs)
      name = member_name(src, field)
      return if name.start_with?("#")
      return read_declaration_metadata(src, field, inputs, outputs) if @strict && %w[ɵcmp ɵdir].include?(name)
      return if inputs.include?(name) || outputs.include?(name)

      init = field.child_by_field_name("value")
      return if init.nil? && !@strict

      decos = decorators(src, field)
      if init&.type == :call_expression
        kind = call_kind(src, init)
        case kind
        when :input then return inputs << name
        when :output then return outputs << name
        when :model then (inputs << name; return outputs << "#{name}Change")
        end
      end
      if decos.include?("Input") then inputs << name
      elsif decos.include?("Output") then outputs << name
      end
    end

    # ng-nudge sees only class properties. A decorated setter or getter is an
    # accessor, so it only appears in strict mode.
    def collect_accessor(src, method, decos, inputs, outputs)
      return unless method.each.any? { |c| %i[get set].include?(c.type) }
      name = member_name(src, method)
      inputs << name if decos.include?("Input") && !inputs.include?(name)
      outputs << name if decos.include?("Output") && !outputs.include?(name)
    end

    # `input(...)`, `input.required(...)`, `output(...)`; strict adds `model`
    # and `outputFromObservable`. ng-nudge accepts any `input.<anything>(...)`.
    def call_kind(src, call)
      fn = call.child_by_field_name("function")
      root = fn.type == :member_expression ? fn.child_by_field_name("object") : fn
      return nil unless root.type == :identifier
      id = src.text_of(root)
      return :input if id == "input"
      return :output if id == "output" && fn.type == :identifier
      return :output if @strict && id == "outputFromObservable" && fn.type == :identifier
      return :model if @strict && id == "model"
      nil
    end

    # A class in a package's .d.ts has no initializers and no decorators. Angular
    # records the inputs and outputs in the types of `static ɵcmp` / `ɵdir`.
    def read_declaration_metadata(src, field, inputs, outputs)
      generic = field.child_by_field_name("type")&.each_named&.first
      args = generic&.child_by_field_name("type_arguments")&.each_named&.to_a or return
      keys = ->(node) { node&.type == :object_type ? node.each_named.select { |p| p.type == :property_signature }.map { |p| member_name(src, p) } : [] }
      keys.(args[3]).each { |n| inputs << n unless inputs.include?(n) }
      keys.(args[4]).each { |n| outputs << n unless outputs.include?(n) }
    end

    def member_name(src, node)
      n = node.child_by_field_name("name")
      n.type == :string ? src.text_of(n)[1..-2] : src.text_of(n)
    end

    # Decorator names. For an exported class tree-sitter hangs the decorators
    # on the export statement, not on the class.
    def decorators(src, holder)
      holder.each_field.select { |f, _| f == "decorator" }.map { |_, d| decorator_name(src, d) }.compact
    end

    def decorator_name(src, deco)
      e = deco.each_named.first
      e = e.child_by_field_name("function") if e.type == :call_expression
      e.type == :identifier ? src.text_of(e) : nil
    end

    # ---- following base classes (what ts-morph's getBaseClass() does) ------

    # Returns [source, class_node] for the class that `cls` extends, or nil.
    def base_class(src, cls)
      heritage = cls.each_named.find { |c| c.type == :class_heritage } or return nil
      value = heritage.each_named.find { |c| c.type == :extends_clause }&.child_by_field_name("value") or return nil
      resolve_expression(src, value)
    end

    def resolve_expression(src, expr)
      case expr.type
      when :identifier then resolve_name(src, src.text_of(expr))
      when :member_expression # ns.Base
        obj = expr.child_by_field_name("object")
        return nil unless obj.type == :identifier
        binding = import_binding(src, src.text_of(obj))
        return nil unless binding && binding[:name] == "*"
        file = resolve_module(binding[:module], src.path) or return nil
        find_export(file, src.text_of(expr.child_by_field_name("property")))
      when :call_expression
        # A mixin: `extends withX(Base)`. Syntax cannot say what the function
        # returns; that takes the type checker. The heuristic guesses the
        # first argument is the class that comes out.
        return nil unless @mixin_heuristic
        arg = expr.child_by_field_name("arguments").each_named.first
        arg && resolve_expression(src, arg)
      end
    end

    def resolve_name(src, name)
      if (binding = import_binding(src, name))
        return nil if binding[:name] == "*"
        file = resolve_module(binding[:module], src.path) or return nil
        return find_export(file, binding[:name])
      end
      local = top_level_classes(src).find { |c| class_name(src, c[:decl]) == name }
      local && [src, local[:decl]]
    end

    # `import X from`, `import { A as B } from`, `import * as N from`.
    def import_binding(src, local_name)
      src.root.each_named.select { |n| n.type == :import_statement }.each do |imp|
        clause = imp.each_named.find { |c| c.type == :import_clause } or next
        mod = string_value(src, imp.child_by_field_name("source"))
        clause.each_named do |part|
          case part.type
          when :identifier
            return { module: mod, name: "default" } if src.text_of(part) == local_name
          when :namespace_import
            return { module: mod, name: "*" } if src.text_of(part.each_named.first) == local_name
          when :named_imports
            part.each_named do |spec|
              imported = src.text_of(spec.child_by_field_name("name"))
              alias_node = spec.child_by_field_name("alias")
              return { module: mod, name: imported } if (alias_node ? src.text_of(alias_node) : imported) == local_name
            end
          end
        end
      end
      nil
    end

    # What `export ... ` makes visible under `name` in `file`, following
    # `export { A as B } from`, `export * from`, `export default X` and
    # `export { default as A } from`.
    def find_export(file, name, seen = Set.new)
      return nil unless seen.add?([file, name])
      src = source(file) or return nil
      star_sources = []
      src.root.each_named do |n|
        next unless n.type == :export_statement
        decl = n.child_by_field_name("declaration")
        decl = decl.each_named.find { |c| CLASS_TYPES.include?(c.type) } if decl&.type == :ambient_declaration
        if decl && CLASS_TYPES.include?(decl.type)
          is_default = n.each.any? { |c| c.type == :default }
          return [src, decl] if is_default ? name == "default" : class_name(src, decl) == name
        end
        if n.each.any? { |c| c.type == :default } && (v = n.child_by_field_name("value")) && v.type == :identifier && name == "default"
          return resolve_name(src, src.text_of(v)) # `export default Foo;`
        end
        from = n.child_by_field_name("source")
        clause = n.each_named.find { |c| c.type == :export_clause }
        if clause
          clause.each_named do |spec|
            orig = src.text_of(spec.child_by_field_name("name"))
            al = spec.child_by_field_name("alias")
            next unless (al ? src.text_of(al) : orig) == name
            if from
              target = resolve_module(string_value(src, from), file) or return nil
              return find_export(target, orig, seen)
            end
            return resolve_name(src, orig)
          end
        elsif from && n.each.any? { |c| c.type == :* }
          star_sources << string_value(src, from)
        end
      end
      star_sources.each do |s|
        target = resolve_module(s, file) or next
        hit = find_export(target, name, seen)
        return hit if hit
      end
      nil
    end

    def string_value(src, str_node) = src.text_of(str_node)[1..-2]

    def class_name(src, decl) = src.text_of(decl.child_by_field_name("name"))

    # Top-level classes, each with the node that carries its decorators.
    def top_level_classes(src)
      src.root.each_named.filter_map do |n|
        if CLASS_TYPES.include?(n.type)
          { decl: n, holder: n }
        elsif n.type == :export_statement
          d = n.child_by_field_name("declaration")
          d = d.each_named.find { |c| CLASS_TYPES.include?(c.type) } if d&.type == :ambient_declaration
          { decl: d, holder: n } if d && CLASS_TYPES.include?(d.type)
        end
      end
    end

    # ---- files, tsconfig and module resolution (ts-morph does all of this) ---

    def source(path)
      path = File.expand_path(path, @src_dir || @root)
      return nil unless File.file?(path)
      @sources[path] ||= begin
        text = File.read(path)
        Source.new(path, text, @parser.parse_string(nil, text).root_node)
      end
    end

    # tsconfig.json is JSON with comments and trailing commas, and may extend
    # another file. Returns { base_url:, paths: } with absolute directories.
    def load_tsconfig(path, seen = [])
      return { base_url: nil, paths: {} } unless File.file?(path) && !seen.include?(path)
      json = JSON.parse(strip_jsonc(File.read(path)))
      options = json["compilerOptions"] || {}
      inherited = json["extends"] ? load_tsconfig(File.expand_path(json["extends"].then { |e| e.end_with?(".json") ? e : "#{e}.json" }, File.dirname(path)), seen + [path]) : { base_url: nil, paths: {} }
      dir = File.dirname(path)
      base_url = options["baseUrl"] ? File.expand_path(options["baseUrl"], dir) : inherited[:base_url]
      paths = options["paths"] ? { dir: base_url || dir, map: options["paths"] } : nil
      { base_url: base_url, paths: paths ? inherited[:paths].merge(paths[:map].transform_values { |v| v.map { |t| File.expand_path(t, paths[:dir]) } }) : inherited[:paths] }
    end

    # Removes comments and trailing commas without touching strings.
    def strip_jsonc(text)
      text.gsub(%r{("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/}m) { $1 || "" }.gsub(/,(\s*[}\]])/, '\1')
    end

    def resolve_module(spec, from_file)
      if spec.start_with?(".")
        return try_file(File.expand_path(spec, File.dirname(from_file)))
      end
      @tsconfig[:paths].each do |pattern, targets|
        regex = Regexp.new("\\A#{Regexp.escape(pattern).sub('\\*', '(.*)')}\\z")
        next unless (m = regex.match(spec))
        targets.each do |t|
          hit = try_file(m[1] ? t.sub("*", m[1]) : t)
          return hit if hit
        end
      end
      if @tsconfig[:base_url] && (hit = try_file(File.join(@tsconfig[:base_url], spec)))
        return hit
      end
      resolve_package(spec, File.dirname(from_file))
    end

    # `a.js` in an import means `a.ts` on disk; a directory means its index.
    def try_file(base)
      candidates = [base, base.sub(/\.(m|c)?js\z/, ".ts")]
      candidates.flat_map { |c| EXTENSIONS.map { |e| c + e } + EXTENSIONS.map { |e| File.join(c, "index#{e}") } }
                .then { |list| [base] + list }
                .find { |f| File.file?(f) }
    end

    # Walks up looking for node_modules/<package>, then reads its package.json
    # for the declaration file; falls back to @types.
    def resolve_package(spec, dir)
      parts = spec.split("/")
      name = spec.start_with?("@") ? parts[0, 2].join("/") : parts[0]
      sub = parts.drop(name.count("/") + 1).join("/")
      loop do
        [name, "@types/#{name.sub('@', '').sub('/', '__')}"].each do |pkg|
          root = File.join(dir, "node_modules", pkg)
          next unless File.directory?(root)
          return try_file(File.join(root, sub)) unless sub.empty?
          manifest = File.file?(File.join(root, "package.json")) ? JSON.parse(File.read(File.join(root, "package.json"))) : {}
          entry = manifest["types"] || manifest["typings"] || manifest.dig("exports", ".", "types") || manifest["main"] || "index"
          hit = try_file(File.join(root, entry.sub(/\.d\.ts\z/, "").sub(/\.js\z/, "")))
          return hit if hit
        end
        parent = File.dirname(dir)
        return nil if parent == dir
        dir = parent
      end
    end
  end
end
