# Ruby plugin, design (b): debt tracking through the post_check hook. The host sends every plugin's
# violations after the checks; this plugin answers with the excused ones, the stale entries, the file to
# write and its own has-debt violations. It shares the TSV and matching code with the host's design (a).
require "json"
require_relative "../../host/debt"

$stdout.sync = true

$stdin.each_line do |line|
  request = JSON.parse(line)
  reply =
    case request["method"]
    when "handshake" then { "result" => { "protocol" => 1, "name" => "debt" } }
    when "post_check" then { "result" => Debt.evaluate(request["params"]) }
    else { "error" => { "code" => "unknown-method", "message" => request["method"] } }
    end
  puts JSON.generate({ "id" => request["id"] }.merge(reply))
rescue Debt::Error => e
  puts JSON.generate({ "id" => request["id"], "error" => { "code" => "debt-file", "message" => e.message } })
end
