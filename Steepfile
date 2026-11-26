# frozen_string_literal: true

# Steep checks lib/ against the signatures in sig/ (rake steep).
D = Steep::Diagnostic

target :lib do
  signature "sig"
  check "lib"

  library "did_you_mean", "minitest", "open3", "pathname"

  configure_code_diagnostics(D::Ruby.default)
end
