# frozen_string_literal: true

# A component's interface file has one interface, whose properties,
# inherited ones included, name each input and output the component has.
# Any property stands for an input or an output, and the interface's
# extra properties and every type go unchecked, as in ng-nudge.
class InterfaceMatchesComponent < CrossLint::Rule
  def initialize
    @members = helper("members")
  end

  def check(artifact)
    component = read(artifact, artifact.path).fetch("component")
    return [] unless component

    interface = artifact.companion("interface")
    interfaces = read(artifact, interface.path).fetch("interfaces")
    unless interfaces.size == 1
      count = interfaces.empty? ? "no interface" : "#{interfaces.size} interfaces"
      return [violation(artifact, "interface file at #{interface.path} has #{count}, where it should have one")]
    end

    names = interfaces.first
    %w[input output].flat_map do |kind|
      (component.fetch("#{kind}s") - names).map do |name|
        # ng-nudge's message, from lib/rule/interface-matches-component.rule.js and lib/artifact/missing-member.js.
        # SPDX-SnippetBegin
        # SPDX-SnippetCopyrightText: 2026 Over The Top Marketing
        # SPDX-License-Identifier: MIT
        violation(artifact, "interface missing #{kind}: #{name}", detail: "#{kind} #{name}")
        # SPDX-SnippetEnd
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
