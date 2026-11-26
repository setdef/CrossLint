# frozen_string_literal: true

# A component's stub has each input and output the component has, by
# name: its @Component class, base classes included, read by the helper.
# A stub's extra members and every type go unchecked, as in ng-nudge.
class StubMatchesComponent < CrossLint::Rule
  def initialize
    @members = helper("members")
  end

  def check(artifact)
    component = read(artifact, artifact.path).fetch("component")
    return [] unless component

    stub = artifact.companion("stub")
    found = read(artifact, stub.path).fetch("component")
    return [violation(artifact, "stub file at #{stub.path} has no @Component class")] unless found

    %w[input output].flat_map do |kind|
      (component.fetch("#{kind}s") - found.fetch("#{kind}s")).map do |name|
        # ng-nudge's message, from lib/rule/stub-matches-component.rule.js and lib/artifact/missing-member.js.
        # SPDX-SnippetBegin
        # SPDX-SnippetCopyrightText: 2026 Over The Top Marketing
        # SPDX-License-Identifier: MIT
        message = "stub missing #{kind}: #{name}"
        # SPDX-SnippetEnd
        violation(artifact, message, detail: "#{kind} #{name}")
      end
    end
  end

  private

  def read(artifact, path)
    tsconfig = artifact.companion("tsconfig")
    raise "reads TypeScript with #{tsconfig.path}, the tsconfig setting's file, which doesn't exist" unless tsconfig.exist?

    answer = @members.call({"tsconfig" => tsconfig.path, "path" => path})
    raise answer.fetch("error") if answer.key?("error")

    answer
  end
end
