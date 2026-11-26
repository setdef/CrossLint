# frozen_string_literal: true

# Steep checks lib/ against the signatures in sig/ (rake steep).
D = Steep::Diagnostic

target :lib do
  signature "sig"
  check "lib"

  library "did_you_mean", "fileutils", "json", "minitest", "open3", "pathname", "securerandom", "timeout"

  configure_code_diagnostics(D::Ruby.default)
end
