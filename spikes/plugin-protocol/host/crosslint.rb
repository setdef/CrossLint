#!/usr/bin/env ruby
# frozen_string_literal: true

# Spike host: runs plugins that speak protocol 1 (see ../README.md).
#
#   crosslint.rb [--root DIR] [--provision] [--timing] [--repeat N] [--lifetime per-check|per-run] PLUGIN_DIR...
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

  def self.which(command)
    return (File.executable?(command) ? command : nil) if command.include?("/")

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { File.join(_1, command) }.find { File.file?(_1) && File.executable?(_1) }
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
      args = (rt["args"] || []).map { _1.gsub("{plugin_dir}", @dir) }
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
        @stdin, @stdout, stderr, @wait = Open3.popen3(@env || {}, *argv_, chdir: @root)
      rescue Errno::ENOENT, Errno::EACCES => e
        fail!("runtime-missing", "could not start #{argv_.first}: #{e.message}")
      end
      @stderr_reader = Thread.new { stderr.read }
      @id = 0
      hello = call("handshake", { "protocol" => PROTOCOL, "host" => "crosslint-spike" })
      fail!("protocol-mismatch", "plugin speaks protocol #{hello["protocol"].inspect}, host speaks #{PROTOCOL}") unless hello["protocol"] == PROTOCOL
      @timings << ["start+handshake", now - t0 - (@provision_s || 0)]
    end

    def check(artifact, items)
      t0 = now
      result = call("check", { "root" => @root, "artifact" => artifact.fetch("name"), "items" => items })
      @timings << ["check", now - t0]
      result.fetch("violations").map { _1.merge("plugin" => @name) }
    rescue KeyError => e
      fail!("bad-response", e.message)
    end

    def stop
      @stdin.close unless @stdin.closed?
      @wait.join(5) || Process.kill("KILL", @wait.pid)
    end

    private

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
      Process.kill("KILL", @wait.pid)
      fail!("timeout", "no answer to #{method} in #{@manifest.fetch("timeout", 60)} s")
    end

    def died
      @stdin.close unless @stdin.closed?
      status = @wait.value
      fail!("exited", "status #{status.exitstatus.inspect} before answering. stderr: #{@stderr_reader.value.strip[0, 300]}")
    end
  end
end

options = { root: Dir.pwd, provision: false, timing: false, repeat: 1, lifetime: nil }
OptionParser.new do |o|
  o.on("--root DIR") { options[:root] = File.expand_path(_1) }
  o.on("--provision") { options[:provision] = true }
  o.on("--timing") { options[:timing] = true }
  o.on("--repeat N", Integer) { options[:repeat] = _1 }
  o.on("--lifetime L", %w[per-check per-run]) { options[:lifetime] = _1 }
end.parse!

violations = []
failures = []
ARGV.each do |dir|
  plugin = Spike::Plugin.new(dir, root: options[:root], provision: options[:provision], lifetime: options[:lifetime])
  plugin.start if plugin.per_run?
  plugin.artifacts.each do |artifact|
    items = plugin.items(artifact)
    plugin.start unless plugin.per_run?
    results = Array.new(options[:repeat]) { plugin.check(artifact, items) }
    violations.concat(results.first)
    plugin.stop unless plugin.per_run?
  end
  plugin.stop if plugin.per_run?
  if options[:timing]
    plugin.timings.each { |what, s| warn format("timing %-28s %-16s %6.0f ms", plugin.name, what, s * 1000) }
  end
rescue Spike::PluginFailure => e
  failures << e
  warn "crosslint: #{e.message}"
end

violations.each { |v| puts "#{v["path"]}: [#{v["plugin"]}/#{v["rule"]}] #{v["message"]}" }
exit 2 unless failures.empty?
exit 1 unless violations.empty?
