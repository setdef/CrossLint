# frozen_string_literal: true

require_relative "../../fault"

raise CrossLint::Core::PluginError, "requires bundler/inline, which CrossLint doesn't offer, since it would install gems into CrossLint's folder"
