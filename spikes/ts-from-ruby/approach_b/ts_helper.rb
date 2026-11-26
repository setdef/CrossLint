# Approach B, Ruby side: run helper.mjs once with Node and read its JSON back.
require "json"
require "open3"

module TsHelper
  Api = Struct.new(:inputs, :outputs)

  class Reader
    def initialize(project_root:, strict: false, node: "node")
      @root = File.expand_path(project_root)
      @strict = strict
      @node = node
      @helper = File.expand_path("helper.mjs", __dir__)
    end

    # One Node process for every file asked about: loading the program is the cost.
    def prepare(components:, interfaces:)
      request = { tsconfig: File.join(@root, "tsconfig.json"), strict: @strict, components: components, interfaces: interfaces }
      out, err, status = Open3.capture3(@node, @helper, stdin_data: JSON.generate(request))
      raise "helper failed (#{status.exitstatus}): #{err}" unless status.success?
      @result = JSON.parse(out)
    end

    def component_api(path)
      api = @result.fetch("components").fetch(path)
      api && Api.new(api["inputs"], api["outputs"])
    end

    def interface_names(path)
      r = @result.fetch("interfaces").fetch(path)
      raise r["error"] if r.is_a?(Hash)
      r
    end
  end
end
