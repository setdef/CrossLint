# Ruby plugin: ng-nudge's rules that read only paths and one TSV file. The host decides which
# rules run on which item (item["rules"]), from the policies in plugin.json.
require "json"

$stdout.sync = true

def exists?(item, companion) = item["companions"][companion]["exists"]

RULES = {
  "spec-exists" => ->(item) { ["spec file missing"] unless exists?(item, "spec") },
  "stub-exists" => ->(item) { ["stub file missing"] unless exists?(item, "stub") },
  "interface-exists" => ->(item) { ["interface file missing"] unless exists?(item, "interface") },
  "prefer-css-over-scss" => ->(item) { ["uses SCSS instead of CSS"] if exists?(item, "scss") && !exists?(item, "css") },
  # One violation per debt entry, the way ng-nudge's has-debt rule reports them (quoting of fields is not handled).
  "has-debt" => ->(item) { File.readlines(item["path"], chomp: true).drop(1).reject(&:empty?).map { _1.split("\t", -1).first(3).join("\t").sub(/\t\z/, "") } },
}.freeze

$stdin.each_line do |line|
  request = JSON.parse(line)
  result =
    case request["method"]
    when "handshake"
      { "protocol" => 1, "name" => "ng-nudge-paths" }
    when "check"
      violations = request["params"]["items"].flat_map do |item|
        (item["rules"] || RULES.keys).flat_map do |rule|
          Array(RULES.fetch(rule).call(item)).map { |message| { "rule" => rule, "path" => item["path"], "message" => message } }
        end
      end
      { "violations" => violations }
    end
  puts JSON.generate(result ? { "id" => request["id"], "result" => result } : { "id" => request["id"], "error" => { "code" => "unknown-method", "message" => request["method"] } })
end
