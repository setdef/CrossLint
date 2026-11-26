# Ruby plugin: every component has a spec. It reads only what the host sends.
require "json"

$stdout.sync = true

$stdin.each_line do |line|
  request = JSON.parse(line)
  result =
    case request["method"]
    when "handshake"
      { "protocol" => 1, "name" => "spec-per-component" }
    when "check"
      missing = request["params"]["items"].reject { _1["companions"]["spec"]["exists"] }
      { "violations" => missing.map { |i| { "rule" => "component-has-spec", "path" => i["path"], "message" => "no spec at #{i["companions"]["spec"]["path"]}" } } }
    end
  reply = result ? { "id" => request["id"], "result" => result } : { "id" => request["id"], "error" => { "code" => "unknown-method", "message" => request["method"] } }
  puts JSON.generate(reply)
end
