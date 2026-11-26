# frozen_string_literal: true

# Debt tracking over every plugin's violations, in ng-nudge's debt.tsv format. Design (a) calls
# Debt.evaluate from the host; design (b) calls it from a plugin (plugins/debt-rb). The input and the
# result are plain JSON-shaped hashes, so a plugin in another language could take the same messages.
#
# input:  root, config (rc.json shape), flags (["update-debt"]), violations (id, plugin, rule, path, message,
#         detail?, artifact, key), ran ([plugin, rule, artifact, key] for each rule that ran on an item),
#         known ([artifact, key] for each item found), rules ([plugin, rule] provided by plugins that worked)
# result: excused (violation ids), violations (new ones), stale, report (lines), failing, writes ([{path, content}])
module Debt
  class Error < StandardError; end

  DEFAULT_FILE = ".config/ng-nudge/debt.tsv"
  HEADER = %w[Rule Artifact Comment].freeze
  Entry = Struct.new(:rule, :key, :comment, :detail, :raw, keyword_init: true)

  # d3-dsv's TSV: a field starting with `"` runs to the closing quote (`""` is a quote); other fields end
  # at a tab or line end. Returns each record's fields and its raw text, so a kept row is written back as it was.
  def self.parse(text)
    s = text.chars
    i = 0
    rows = []
    while i < s.size
      start = i
      fields = []
      loop do
        f = +""
        if s[i] == '"'
          i += 1
          while i < s.size
            if s[i] == '"' && s[i + 1] == '"' then f << '"' and i += 2
            elsif s[i] == '"' then i += 1 and break
            else f << s[i] and i += 1
            end
          end
        else
          f << s[i] and i += 1 until i >= s.size || "\t\n\r".include?(s[i])
        end
        fields << f
        break unless s[i] == "\t"

        i += 1
      end
      raw = s[start...i].join
      i += 1 if s[i] == "\r"
      i += 1 if s[i] == "\n"
      rows << { fields: fields, raw: raw } unless fields == [""]
    end
    rows
  end

  def self.field(value) = value.match?(/["\t\n\r]/) ? %("#{value.gsub('"', '""')}") : value

  # A missing file is no debt. Keys use "/" on every system: a file written on Windows has "\".
  def self.read(path)
    return [HEADER, []] unless File.file?(path)

    rows = parse(File.read(path, encoding: "UTF-8").delete_prefix("﻿"))
    header = rows.shift&.fetch(:fields) || HEADER
    col = ->(r, name) { (i = header.index(name)) && r[:fields][i].to_s }
    entries = rows.each_with_index.map do |r, i|
      rule = col.(r, "Rule")
      artifact = col.(r, "Artifact")
      raise Error, "#{DEFAULT_FILE} row #{i + 2}: Rule column is empty or missing" if rule.to_s.empty?
      raise Error, "#{DEFAULT_FILE} row #{i + 2}: Artifact column is empty or missing" if artifact.to_s.empty?

      detail = col.(r, "Detail")
      Entry.new(rule: rule, key: artifact.tr("\\", "/"), comment: col.(r, "Comment").to_s,
                detail: (detail unless detail.to_s.empty?), raw: (r[:raw] unless artifact.include?("\\")))
    end
    [header, entries]
  end

  def self.serialize(header, entries)
    cells = { "Rule" => :rule, "Artifact" => :key, "Comment" => :comment, "Detail" => :detail }
    rows = entries.map { |e| e.raw || header.map { |h| field(e[cells.fetch(h, :comment)].to_s) }.join("\t") }
    ([header.map { field(_1) }.join("\t")] + rows).join("\n") + "\n"
  end

  # ng-nudge's withComment: a commented entry's severity is capped. true or "warning" -> warning,
  # "none" -> not reported, {maxSeverity, matching} -> the cap applies to comments the pattern matches.
  def self.severity(entry, base, with_comment)
    cap = ->(max) { max == "none" ? nil : (max == "warning" ? "warning" : base) }
    return base if entry.comment.empty? || !with_comment

    case with_comment
    when true then cap.("warning")
    when String then cap.(with_comment)
    when Hash then !with_comment["matching"] || Regexp.new(with_comment["matching"]).match?(entry.comment) ? cap.(with_comment["maxSeverity"]) : base
    else base
    end
  end

  def self.evaluate(input)
    root, config, flags, violations, ran, known, provided = input.values_at("root", "config", "flags", "violations", "ran", "known", "rules")
    update = flags.include?("update-debt")
    path = File.join(root, DEFAULT_FILE)
    header, entries = read(path)
    rule_is = ->(e, plugin, rule) { e.rule == rule || e.rule == "#{plugin}/#{rule}" }
    key_is = ->(e, key, artifact) { e.key == key || e.key == "#{key}.#{artifact}" }
    match = ->(e, v) { rule_is.(e, v["plugin"], v["rule"]) && key_is.(e, v["key"], v["artifact"]) }

    # Each entry excuses one violation (rule and key, and detail when the row has one), so a row
    # never excuses violations that appeared after it was written.
    left = violations.dup
    matched = {}.compare_by_identity
    ambiguous = {}.compare_by_identity
    entries.select(&:detail).each do |e|
      v = left.find { match.(e, _1) && _1["detail"] == e.detail } or next
      left.delete(v)
      matched[e] = true
    end
    entries.reject { matched.key?(_1) || _1.detail }.each do |e|
      candidates = left.select { match.(e, _1) }
      if candidates.map { _1["artifact"] }.uniq.size > 1 then ambiguous[e] = candidates.map { _1["artifact"] }.uniq # a plain key two artifacts share
      elsif (v = candidates.first) then left.delete(v) and matched[e] = true
      end
    end

    # An unmatched entry is stale (debt paid off) only when its rule ran on its artifact, or the artifact is gone.
    # A rule that was disabled, did not apply, or whose plugin failed leaves its entries alone.
    stale = []
    unchecked = []
    entries.reject { matched.key?(_1) || ambiguous.key?(_1) }.each do |e|
      if provided.none? { |plugin, rule| rule_is.(e, plugin, rule) } then unchecked << [e, "no plugin that ran provides it"]
      elsif ran.any? { |plugin, rule, artifact, key| rule_is.(e, plugin, rule) && key_is.(e, key, artifact) } then stale << e
      elsif known.none? { |artifact, key| key_is.(e, key, artifact) } then stale << e
      else unchecked << [e, "it did not run on this artifact (disabled, or its policy does not apply)"]
      end
    end

    report = []
    kept = entries
    if update
      # A written key needs its artifact when one rule ran on two artifacts with that key.
      shared = ran.group_by { |_, rule, _, key| [rule, key] }.select { |_, rows| rows.map { _1[2] }.uniq.size > 1 }.keys
      twice = provided.map(&:last).tally.select { |_, n| n > 1 }.keys
      added = left.map do |v|
        comment = entries.find { ambiguous.key?(_1) && match.(_1, v) }&.comment.to_s # an ambiguous row's comment goes to each artifact
        Entry.new(rule: twice.include?(v["rule"]) ? "#{v["plugin"]}/#{v["rule"]}" : v["rule"],
                  key: shared.include?([v["rule"], v["key"]]) ? "#{v["key"]}.#{v["artifact"]}" : v["key"], comment: comment, detail: v["detail"])
      end.sort_by { [_1.rule, _1.key, _1.detail.to_s] }
      kept = entries.reject { |e| stale.include?(e) || ambiguous.key?(e) }
      header += ["Detail"] if added.any?(&:detail) && !header.include?("Detail")
      entries_after = kept + added
      writes = [{ "path" => DEFAULT_FILE, "content" => serialize(header, entries_after) }]
      report << "Updated #{DEFAULT_FILE} (#{entries_after.size} entries): #{added.size} added, #{entries.size - kept.size} removed"
      entries = entries_after
    else
      writes = []
      unless stale.empty?
        report << "★  Debt paid off:" << stale.map { "   #{_1.key} no longer owes #{_1.rule}" } << "Run --update-debt to update #{DEFAULT_FILE}"
      end
      unless ambiguous.empty?
        report << "Debt that two artifacts share (write the key with its artifact, like app/foo/foo.service):"
        report << ambiguous.map { |e, arts| "   #{e.key} #{e.rule}: #{arts.join(" and ")}" }
      end
    end
    report << "Debt not checked in this run:" << unchecked.map { |e, why| "   #{e.key} #{e.rule}: #{why}" } unless unchecked.empty?

    # has-debt: one violation per entry, in the file as it is after any update.
    cfg = config.dig("rules", "has-debt") || {}
    found = []
    if cfg.key?("withComment") && cfg["enabled"] != false
      base = cfg["severity"] == "warning" ? "warning" : "error"
      entries.each do |e|
        sev = severity(e, base, cfg["withComment"]) or next
        found << { "plugin" => "debt", "rule" => "has-debt", "path" => DEFAULT_FILE, "severity" => sev,
                   "message" => [e.rule, e.key, e.comment].reject(&:empty?).join("\t") }
      end
    end

    { "excused" => (update ? violations : violations - left).map { _1["id"] }, "violations" => found,
      "stale" => stale.map { { "rule" => _1.rule, "key" => _1.key } }, "report" => report.flatten,
      "failing" => !update && !(stale.empty? && ambiguous.empty?), "writes" => writes }
  rescue Errno::EACCES, Errno::EISDIR => e
    raise Error, e.message
  end
end
