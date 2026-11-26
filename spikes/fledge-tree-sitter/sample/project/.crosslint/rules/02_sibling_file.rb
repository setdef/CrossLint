# A rule that reads a helper beside it, and a file of the project's own.
require_relative "helpers/names"

TsSpike.rule("class-name-suffix") do |facts|
  facts[:classes].filter_map do |klass|
    "class #{klass[:name]} should end in Component" unless Names.component?(klass[:name])
  end
end
