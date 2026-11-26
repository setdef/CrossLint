# A rule file that brings a pure-Ruby library in its own folder, on $LOAD_PATH.
$LOAD_PATH.unshift(File.join(__dir__, "vendor"))
require "tiny_counter"

TsSpike.rule("count-classes") do |facts|
  ["#{TinyCounter.count(facts[:classes])} class(es)"]
end
