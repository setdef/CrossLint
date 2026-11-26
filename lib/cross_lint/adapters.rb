# frozen_string_literal: true

module CrossLint
  module Adapters
  end
end

require_relative "adapters/kdl_document"
require_relative "adapters/kdl_configuration"
require_relative "adapters/kdl_plugin_manifests"
require_relative "adapters/memory_configuration"
require_relative "adapters/memory_plugin_manifests"
require_relative "adapters/git_project_files"
require_relative "adapters/memory_project_files"
require_relative "adapters/file_plugin_ruby"
require_relative "adapters/memory_plugin_ruby"
require_relative "adapters/process_helpers"
require_relative "adapters/memory_helpers"
require_relative "adapters/text_report"
require_relative "adapters/json_report"
require_relative "adapters/memory_report"
require_relative "adapters/tsv_debt_files"
require_relative "adapters/memory_debt_files"
