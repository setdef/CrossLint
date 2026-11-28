# frozen_string_literal: true

# Tells the license notice that belongs to a package from the notice of another work.
#
# A source file that carries a license notice may be a file of the package,
# with the header its author gave it, or code that the package
# bundles from another project, whose license may ask for its text to go
# with every copy (tasks/bundled_works.rb). The notice in the file belongs
# to the package when the package's npm entry already credits what the
# notice says: a license that its package.json declares, and copyright
# holders that its license files list. A notice that states another
# license, lists another holder, or lists no holder is another work's, and
# so is any notice in a file that has both kinds.
module OwnNotices
  # What each phrase that starts a license notice says the license is, as
  # the SPDX ids it can be.
  LICENSES = {
    "Permission is hereby granted" => %w[MIT],
    "Permission to use, copy, modify" => %w[ISC 0BSD],
    "Redistribution and use in source" => %w[BSD-2-Clause BSD-3-Clause],
    "Licensed under the Apache License" => %w[Apache-2.0],
  }.freeze

  # The tag that gives a license as an SPDX expression, and the phrase
  # that starts a notice and doesn't say which license it is.
  TAG = "SPDX-License-Identifier"
  TAGGED = /#{TAG}:[ \t]*([^\r\n*]*)/
  ANY_LICENSE = "Licensed under the"

  # What starts the license notice of a work in a source file.
  NOTICE = Regexp.union(*LICENSES.keys, ANY_LICENSE, TAG)

  # What a package's npm entry credits: the SPDX ids of the +licenses+
  # its package.json declares, and the +holders+ of copyright its license
  # files list, each written as holder() writes it.
  Credit = Data.define(:licenses, :holders) do
    # Whether the notice in +text+ belongs to the package: it lists at least
    # one holder, every holder it lists is one of the +holders+, and every
    # license it states is one of the +licenses+.
    def covers?(text)
      text = OwnNotices.utf8(text)
      named = OwnNotices.holders(text)
      named.any? && (named - holders).empty? && text.scan(NOTICE).uniq.all? { |phrase| states?(phrase, text) }
    end

    private

    def states?(phrase, text)
      return tagged(text).then { |ids| ids.any? && (ids - licenses).empty? } if phrase == TAG

      LICENSES.fetch(phrase, []).intersect?(licenses)
    end

    def tagged(text) = text.scan(TAGGED).flatten.flat_map { |expression| OwnNotices.licenses(expression) }
  end

  module_function

  # The Credit of a package that declares +license+, an SPDX expression
  # (nil when it declares none), and whose license files have +texts+.
  def credit(license, texts)
    Credit.new(licenses: licenses(license.to_s), holders: texts.flat_map { |text| holders(utf8(text)) }.uniq)
  end

  # The SPDX ids in +expression+.
  def licenses(expression) = expression.scan(/[A-Za-z0-9.+-]+/) - %w[AND OR WITH]

  # The copyright holders that +text+ lists, one for each line that has
  # Copyright in it, less the years, the copyright sign, and what is not
  # a letter or a digit, in lower case, so that the holder of one file
  # equals the same holder in another. A line with no holder gives
  # none.
  def holders(text)
    text.scan(/Copyright[^\r\n]*/).map do |line|
      line.delete_prefix("Copyright").gsub(/\(c\)|©|&copy;/i, "").gsub(/\b\d{4}\b/, "").sub(/all rights reserved/i, "").gsub(/[^\p{L}\p{N}]+/, " ").strip.downcase
    end.reject(&:empty?)
  end

  # +text+ read as UTF-8, with a byte that isn't valid replaced.
  def utf8(text) = text.dup.force_encoding(Encoding::UTF_8).scrub
end
