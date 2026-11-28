# frozen_string_literal: true

module CrossLint
  module Core
    class FetchError < StandardError
      def self.scheme(url, schemes) = new("#{url} doesn't start with #{schemes.join(' or ')}")

      def self.bad_ref(ref) = new("#{ref.dump} is neither a tag name nor a full 40-character commit SHA")

      def self.branch(ref) = new("#{ref} is a branch, and a ref is a tag or a full 40-character commit SHA")

      def self.no_tag(ref) = new("the repository has no tag #{ref}, and a ref is a tag or a full 40-character commit SHA")

      def self.no_commit(sha) = new("the repository has no commit #{sha}")
    end
  end
end
