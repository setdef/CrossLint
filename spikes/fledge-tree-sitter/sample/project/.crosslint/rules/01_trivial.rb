# A trivial project-local rule: a class with an @Input() member must itself
# carry a decorator.
TsSpike.rule("input-needs-decorated-class") do |facts|
  facts[:classes].filter_map do |klass|
    has_input = klass[:members].any? { |m| m[:decorators].any? { |d| d.start_with?("@Input") } }
    "class #{klass[:name]} has @Input() members and no decorator" if has_input && klass[:decorators].empty?
  end
end
