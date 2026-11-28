# frozen_string_literal: true

# Lists each public class, module, interface, constant, method, and
# attribute in CrossLint's signatures that has no comment, and exits with
# 1 when there is one (rake rbs:comments). The comments are CrossLint's
# documentation, so they live in sig/, and lib/ has a comment only where
# the code needs a reason.
#
# A class or module reopened in several files needs its comment in one.

require "rbs"

module SignatureComments
  Members = RBS::AST::Members
  Declarations = RBS::AST::Declarations

  # A declaration: where it is, its name, and whether it has a comment.
  Found = Data.define(:file, :line, :name, :commented)

  module_function

  def missing(sources)
    found = sources.flat_map do |file, source|
      _, _, declarations = RBS::Parser.parse_signature(RBS::Buffer.new(name: file, content: source))
      declarations.flat_map { |declaration| walk(declaration, file, "") }
    end
    commented = found.select(&:commented).map(&:name)
    found.reject { |each| commented.include?(each.name) }.uniq(&:name)
  end

  def walk(declaration, file, outer)
    name = "#{outer}#{declaration.name.to_s.delete_prefix('::')}"
    found = [Found.new(file:, line: line(declaration), name:, commented: !declaration.comment.nil?)]
    return found unless declaration.respond_to?(:members)

    visibility = :public
    found + declaration.members.flat_map do |member|
      case member
      when Members::Private
        visibility = :private
        []
      when Members::Public
        visibility = :public
        []
      when Declarations::Base
        walk(member, file, "#{name}::")
      when Members::MethodDefinition, Members::AttrReader, Members::AttrWriter, Members::AttrAccessor
        next [] if (member.visibility || visibility) == :private

        prefix = (member.respond_to?(:kind) && member.kind == :singleton) ? "." : "#"
        [Found.new(file:, line: line(member), name: "#{name}#{prefix}#{member.name}", commented: !member.comment.nil?)]
      else
        []
      end
    end
  end

  def line(node) = node.location.start_line
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("..", __dir__)
  files = Dir.glob("sig/{cross_lint.rbs,cross_lint/**/*.rbs}", base: root).sort
  missing = SignatureComments.missing(files.map { |file| [file, File.read(File.join(root, file))] })
  missing.each { |found| warn "rake rbs:comments: #{found.file}:#{found.line}: #{found.name} has no comment" }
  exit(missing.empty? ? 0 : 1)
end
