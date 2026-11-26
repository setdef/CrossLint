# frozen_string_literal: true

module CrossLint
  module Core
    class Stale < Data.define(:plugin, :policy, :artifact, :file, :line, :message); end

    class StepInput < Data.define(:project, :plugin, :violations, :faulted, :command); end

    class StepResult < Data.define(:excused, :violations, :stale, :notices, :wrote, :summary); end
  end
end
