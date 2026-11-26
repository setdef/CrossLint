# frozen_string_literal: true

# Steep checks lib/ against the signatures in sig/ (rake steep).
D = Steep::Diagnostic

target :lib do
  signature "sig"
  check "lib"

  library "did_you_mean"

  configure_code_diagnostics(D::Ruby.default)
end
