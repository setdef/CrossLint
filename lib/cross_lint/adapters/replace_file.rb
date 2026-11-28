# frozen_string_literal: true

require "fileutils"
require "securerandom"

module CrossLint
  module Adapters
    module ReplaceFile
      # Writes beside the file, to a file named by 128 random bits, and renames
      # it over the file, so a write that stops partway leaves the file as it
      # was and never touches another file. The new file keeps the old one's
      # permissions.
      def self.call(full, contents)
        temporary = File.join(File.dirname(full), ".crosslint-#{SecureRandom.hex}.tmp")
        begin
          File.binwrite(temporary, contents)
          File.chmod(File.stat(full).mode, temporary) if File.file?(full)
          File.rename(temporary, full)
        ensure
          FileUtils.rm_f(temporary)
        end
      end
    end
  end
end
