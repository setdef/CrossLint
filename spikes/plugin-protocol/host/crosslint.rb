#!/usr/bin/env ruby
# frozen_string_literal: true

# Spike host: runs plugins that speak protocol 1 (see ../README.md).
#
#   crosslint.rb [--root DIR] [--config FILE] [--provision] [--timing] [--repeat N]
#                [--lifetime per-check|per-run] PLUGIN_DIR...
#
# Exit status: 0 no violations, 1 violations, 2 a plugin failed.

require "json"
require "open3"
require "optparse"
require "rbconfig"
require "timeout"

module Spike
  PROTOCOL = 1

  class PluginFailure < StandardError
    attr_reader :kind

    def initialize(plugin, kind, message)
      @kind = kind
      super("plugin #{plugin}: #{kind}: #{message}")
    end
  end

  def self.windows? = Gem.win_platform?

  def self.which(command)
    return (File.executable?(command) ? command : nil) if command.include?("/")

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { File.join(_1, command) }.find { File.file?(_1) && File.executable?(_1) }
  end

  # Processes the host started and has not yet reaped, so that an exit or a signal can end them.
  LIVE = {}
  at_exit { LIVE.each_key { kill_tree(_1) } }

  # Ends a plugin and everything it started: the process group on Unix, the process tree on Windows.
  def self.kill_tree(pid)
    if windows?
      system("taskkill", "/T", "/F", "/PID", pid.to_s, out: File::NULL, err: File::NULL)
    else
      begin
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end
  end

  # A policy's condition, as data. See the README for the list.
  def self.holds?(cond, item, artifact, config, root, who)
    bad = ->(why) { raise PluginFailure.new(who, "bad-manifest", why) }
    case cond
    when nil, true then true
    when Hash
      if cond.key?("all") then cond["all"].all? { holds?(_1, item, artifact, config, root, who) }
      elsif cond.key?("any") then cond["any"].any? { holds?(_1, item, artifact, config, root, who) }
      elsif cond.key?("not") then !holds?(cond["not"], item, artifact, config, root, who)
      elsif cond.key?("companion")
        c = item["companions"][cond["companion"]] or bad.("no companion #{cond["companion"].inspect} on artifact #{artifact["name"]}")
        c["exists"] == cond.fetch("exists", true)
      elsif cond.key?("expects") then Array(artifact["expects"]).include?(cond["expects"])
      elsif cond.key?("config")
        present = !config.dig(*cond["config"].split(".")).nil?
        present == cond.fetch("present", true)
      elsif cond.key?("lines")
        n = File.foreach(File.join(root, item["path"])).count
        cond["lines"].all? { |op, v| { "gt" => n > v, "gte" => n >= v, "eq" => n == v }.fetch(op) { bad.("unknown comparison #{op.inspect}") } }
      else bad.("unknown condition #{cond.keys.first.inspect}")
      end
    else bad.("a condition is an object, found #{cond.inspect}")
    end
  end

  class Plugin
    attr_reader :name, :manifest, :timings

    def initialize(dir, root:, provision:, lifetime: nil)
      @dir = File.expand_path(dir)
      @root = root
      @provision = provision
      @manifest = JSON.parse(File.read(File.join(@dir, "plugin.json")))
      @name = @manifest.fetch("name")
      @lifetime = lifetime || @manifest.fetch("lifetime", "per-check")
      @timings = []
      fail!("protocol-mismatch", "manifest says protocol #{@manifest["protocol"].inspect}, host speaks #{PROTOCOL}") unless @manifest["protocol"] == PROTOCOL
    end

    def per_run? = @lifetime == "per-run"

    def artifacts = @manifest.fetch("artifacts")

    def artifact(name) = artifacts.find { _1["name"] == name } || fail!("bad-manifest", "no artifact #{name.inspect}")

    # Without `policies`, each artifact gets one policy that always applies and runs whatever the plugin runs.
    def policies = @manifest["policies"] || artifacts.map { { "name" => _1["name"], "artifacts" => [_1["name"]] } }

    def declares?(rule) = !@manifest.key?("rules") || @manifest["rules"].any? { _1["name"] == rule }

    # Builds the facts the host already knows: matched paths and which companions exist.
    def items(artifact)
      Dir.glob(artifact.fetch("match"), base: @root).sort.map do |path|
        dir = File.dirname(path)
        base = File.basename(path).split(".").first
        companions = artifact.fetch("companions", {}).transform_values do |template|
          p = template.gsub("{dir}", dir).gsub("{base}", base)
          { "path" => p, "exists" => File.exist?(File.join(@root, p)) }
        end
        { "path" => path, "companions" => companions }
      end
    end

    # Resolves the runtime: on PATH, else provisioned with mise when allowed, else a named failure.
    def argv
      rt = @manifest.fetch("runtime")
      cmd = rt.fetch("command").sub("{host_ruby}", RbConfig.ruby)
      args = (rt["args"] || []).map { _1.gsub("{plugin_dir}", @dir).gsub("{host_ruby}", RbConfig.ruby) }
      if Spike.which(cmd)
        check_version(cmd, rt["min_version"]) if rt["min_version"]
        missing = (rt["also"] || []).reject { Spike.which(_1) }
        fail!("runtime-missing", "needs #{missing.join(", ")} on PATH") unless missing.empty?
        [cmd, *args]
      elsif @provision && (spec = rt.dig("provision", "mise"))
        fail!("runtime-missing", "needs #{cmd}, and mise is not on PATH to provision #{spec}") unless Spike.which("mise")
        # Install first, outside the protocol timeout; MISE_NO_CONFIG keeps the user's mise config from adding tools.
        @env = { "MISE_NO_CONFIG" => "1" }
        t0 = now
        out, status = Open3.capture2e(@env, "mise", "install", spec)
        fail!("provision-failed", "mise install #{spec}: #{out.strip[-300..]}") unless status.success?
        @provision_s = now - t0
        @timings << ["provision #{spec}", @provision_s]
        ["mise", "x", spec, "--", cmd, *args]
      else
        hint = rt.dig("provision", "mise") ? " (rerun with --provision to install #{rt.dig("provision", "mise")} with mise)" : ""
        fail!("runtime-missing", "needs #{cmd} on PATH#{hint}")
      end
    end

    def start
      t0 = now
      argv_ = argv
      begin
        # pgroup: true puts the plugin in a group of its own, so the host can end it and its children together.
        @stdin, @stdout, stderr, @wait = Open3.popen3(@env || {}, *argv_, chdir: @root, pgroup: true)
      rescue Errno::ENOENT, Errno::EACCES => e
        fail!("runtime-missing", "could not start #{argv_.first}: #{e.message}")
      end
      LIVE[@wait.pid] = true
      @stderr_reader = Thread.new { stderr.read }
      @id = 0
      hello = call("handshake", { "protocol" => PROTOCOL, "host" => "crosslint-spike" })
      fail!("protocol-mismatch", "plugin speaks protocol #{hello["protocol"].inspect}, host speaks #{PROTOCOL}") unless hello["protocol"] == PROTOCOL
      @timings << ["start+handshake", now - t0 - (@provision_s || 0)]
    end

    def check(artifact, items)
      t0 = now
      result = call("check", { "root" => @root, "artifact" => artifact, "items" => items })
      @timings << ["check", now - t0]
      result.fetch("violations").map { _1.merge("plugin" => @name) }
    rescue KeyError => e
      fail!("bad-response", e.message)
    end

    def stop
      return unless @wait

      @stdin.close unless @stdin.closed?
      @wait.join(5) || Spike.kill_tree(@wait.pid)
      reap
      @wait = nil
    end

    private

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Ends whatever the plugin left in its group, and forgets the process.
    def reap
      Spike.kill_tree(@wait.pid) unless Spike.windows?
      LIVE.delete(@wait.pid)
    end

    def check_version(cmd, minimum)
      out, = Open3.capture2e(cmd, "--version")
      found = out[/\d+(\.\d+)+/]
      fail!("runtime-too-old", "needs #{cmd} >= #{minimum}, found #{found || out.strip.inspect}") unless found && Gem::Version.new(found) >= Gem::Version.new(minimum)
    end

    def fail!(kind, message) = raise(PluginFailure.new(@name || File.basename(@dir), kind, message))

    def call(method, params)
      @id += 1
      begin
        @stdin.puts JSON.generate("id" => @id, "method" => method, "params" => params)
      rescue Errno::EPIPE
        died
      end
      line = Timeout.timeout(@manifest.fetch("timeout", 60)) { @stdout.gets }
      died if line.nil?
      begin
        msg = JSON.parse(line)
      rescue JSON::ParserError
        fail!("bad-json", "stdout line was not JSON: #{line[0, 80].inspect}")
      end
      fail!("bad-response", "answered id #{msg["id"].inspect} to request #{@id}") unless msg["id"] == @id
      if (err = msg["error"])
        fail!(err["code"] || "plugin-error", err["message"])
      end
      msg.fetch("result") { fail!("bad-response", "neither result nor error") }
    rescue Timeout::Error
      Spike.kill_tree(@wait.pid)
      reap
      fail!("timeout", "no answer to #{method} in #{@manifest.fetch("timeout", 60)} s")
    end

    def died
      @stdin.close unless @stdin.closed?
      status = @wait.value
      reap
      fail!("exited", "status #{status.exitstatus.inspect} before answering. stderr: #{@stderr_reader.value.strip[0, 300]}")
    end
  end
end

options = { root: Dir.pwd, provision: false, timing: false, repeat: 1, lifetime: nil, config: {} }
OptionParser.new do |o|
  o.on("--root DIR") { options[:root] = File.expand_path(_1) }
  o.on("--config FILE") { options[:config] = JSON.parse(File.read(_1)) }
  o.on("--provision") { options[:provision] = true }
  o.on("--timing") { options[:timing] = true }
  o.on("--repeat N", Integer) { options[:repeat] = _1 }
  o.on("--lifetime L", %w[per-check per-run]) { options[:lifetime] = _1 }
end.parse!

violations = []
failures = []
fail_with = lambda do |e|
  failures << e
  warn "crosslint: #{e.message}"
end

loaded = ARGV.filter_map do |dir|
  Spike::Plugin.new(dir, root: options[:root], provision: options[:provision], lifetime: options[:lifetime])
rescue Spike::PluginFailure => e
  fail_with.(e)
  nil
end

# Apply the policies: which rules run on which artifacts. plan[target plugin][[owner, artifact]] = items by path.
plan = Hash.new { |h, k| h[k] = {} }
loaded.each do |owner|
  owner.policies.each do |policy|
    Array(policy.fetch("artifacts")).each do |artifact_name|
      artifact = owner.artifact(artifact_name)
      owner.items(artifact).each do |item|
        next unless Spike.holds?(policy["when"], item, artifact, options[:config], options[:root], owner.name)

        # A rule is "name" (the policy's own plugin) or "plugin/name". No `rules` means the plugin decides.
        targets = (policy["rules"] || [nil]).map do |ref|
          next [owner, nil] unless ref

          pname, rule = ref.include?("/") ? ref.split("/", 2) : [owner.name, ref]
          target = loaded.find { _1.name == pname } or raise Spike::PluginFailure.new(owner.name, "rule-unknown", "policy #{policy["name"]} lists #{ref}, and no plugin #{pname} was given")
          raise Spike::PluginFailure.new(owner.name, "rule-unknown", "policy #{policy["name"]} lists #{ref}, which #{pname} does not declare") unless target.declares?(rule)

          [target, rule]
        end
        targets.each do |target, rule|
          group = (plan[target][[owner.name, artifact_name]] ||= {})
          entry = (group[item["path"]] ||= item.dup)
          next unless rule

          entry["rules"] ||= []
          disabled = options[:config].dig("rules", rule, "enabled") == false
          entry["rules"] << rule unless disabled || entry["rules"].include?(rule)
        end
      end
    end
  end
rescue Spike::PluginFailure => e
  fail_with.(e)
end

loaded.each do |plugin|
  groups = plan.fetch(plugin, {})
  begin
    plugin.start if plugin.per_run? && !groups.empty?
    groups.each do |(_owner, artifact_name), by_path|
      begin
        plugin.start unless plugin.per_run?
        results = Array.new(options[:repeat]) { plugin.check(artifact_name, by_path.values) }
        violations.concat(results.first)
      ensure
        plugin.stop unless plugin.per_run?
      end
    end
  rescue Spike::PluginFailure => e
    fail_with.(e)
  ensure
    plugin.stop if plugin.per_run? && !groups.empty?
  end
  if options[:timing]
    plugin.timings.each { |what, s| warn format("timing %-28s %-16s %6.0f ms", plugin.name, what, s * 1000) }
  end
end

violations.each { |v| puts "#{v["path"]}: [#{v["plugin"]}/#{v["rule"]}] #{v["message"]}" }
exit 2 unless failures.empty?
exit 1 unless violations.empty?
