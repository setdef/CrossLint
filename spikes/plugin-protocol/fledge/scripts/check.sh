#!/usr/bin/env bash

# Build the app for this computer, then install it through mise and run
# run.sh against it. See build.sh and install-check.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$here/scripts/build.sh"
archive="$(ls "$here"/dist/*.tar.gz "$here"/dist/*.zip 2>/dev/null | head -1 || true)"
echo "== archive: $archive"
bash "$here/scripts/install-check.sh" "$archive"
