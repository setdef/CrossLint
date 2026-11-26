# Runs one approach over the fixture and compares what it collects with an
# expected file. Usage:
#   ruby check.rb a|b [--strict] [--mixin-heuristic]
# Without --strict, the expectation is what ng-nudge's code collects
# (expected/ng-nudge.json). With --strict it is what Angular treats as inputs
# and outputs (expected/angular.json).
require "json"

here = __dir__
approach = ARGV.shift or abort "usage: check.rb a|b [--strict] [--mixin-heuristic]"
strict = ARGV.include?("--strict")
mixin = ARGV.include?("--mixin-heuristic")
fixture = File.join(here, "fixture")
expected = JSON.parse(File.read(File.join(here, "expected", strict ? "angular.json" : "ng-nudge.json")))

reader =
  case approach
  when "a"
    require_relative "approach_a/ts_reader"
    grammar = ENV.fetch("TS_GRAMMAR") { Dir[File.join(here, "build", "libtree-sitter-typescript.*")].first }
    TsReader::Reader.new(grammar: grammar, project_root: fixture, strict: strict, mixin_heuristic: mixin)
  when "b"
    require_relative "approach_b/ts_helper"
    TsHelper::Reader.new(project_root: fixture, strict: strict)
  else abort "unknown approach #{approach}"
end

ids = expected.keys
path = ->(id, suffix) { File.join(fixture, "src/app/#{id}/#{id}.component#{suffix}") }
reader.prepare(components: ids.flat_map { |i| [path.(i, ".ts"), path.(i, ".stub.ts")] }, interfaces: ids.map { |i| path.(i, ".i.d.ts") }) if reader.respond_to?(:prepare)

api = ->(file) { (a = reader.component_api(file)) && { "inputs" => a.inputs.sort, "outputs" => a.outputs.sort } }
missing = lambda do |from, other_in, other_out|
  from["inputs"].reject { |n| other_in.include?(n) }.map { |n| "input: #{n}" } +
    from["outputs"].reject { |n| other_out.include?(n) }.map { |n| "output: #{n}" }
end

failures = 0
ids.each do |id|
  comp = api.(path.(id, ".ts"))
  stub = api.(path.(id, ".stub.ts"))
  iface = reader.interface_names(path.(id, ".i.d.ts")).sort
  violations = []
  if comp && stub then violations += missing.(comp, stub["inputs"], stub["outputs"]).map { |m| "stub missing #{m}" } end
  if comp && iface then violations += missing.(comp, iface, iface).map { |m| "interface missing #{m}" } end
  got = { "component" => comp, "stub" => stub, "interface" => iface, "violations" => violations.sort }
  want = expected[id].merge("violations" => expected[id]["violations"].sort)
  if got == want
    puts "ok    #{id}"
  else
    failures += 1
    puts "FAIL  #{id}"
    %w[component stub interface violations].each do |k|
      next if got[k] == want[k]
      if k == "violations" || k == "interface"
        puts "        #{k}: wanted #{want[k].inspect}, got #{got[k].inspect}"
      else
        %w[inputs outputs].each do |side|
          next if got[k]&.dig(side) == want[k]&.dig(side)
          puts "        #{k} #{side}: wanted #{want[k]&.dig(side).inspect}, got #{got[k]&.dig(side).inspect}"
        end
      end
    end
  end
end
puts "#{ids.size - failures}/#{ids.size} match#{' (strict)' if strict}#{' (mixin heuristic)' if mixin}"
exit(failures.zero? ? 0 : 1)
