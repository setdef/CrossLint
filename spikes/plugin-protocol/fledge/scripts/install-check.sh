#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Install the built app through mise, as setdef/Fledge#123 describes, into an
# empty mise data folder, with Node and jq beside it and no Ruby on PATH, then
# run the whole of ../../run.sh against the installed app. Usage:
#
#   scripts/install-check.sh ARCHIVE
#
# ARCHIVE is the .tar.gz or .zip that `fledge build` wrote. mise downloads it
# from a file:// URL, with strip_components = 1 and bin_path = "." (MISE_OPTS
# changes them). Needs network access for Node, jq and, in run.sh, typescript.
set -uo pipefail

archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s)" in
  MINGW*|MSYS*) exe=crosslint-spike.exe; archive="$(cygpath -m "$archive")"; url="file:///$archive" ;;
  *) exe=crosslint-spike; url="file://$archive" ;;
esac
opts="${MISE_OPTS-strip_components = 1, bin_path = \".\"}"

# Drop every PATH folder that holds a Ruby, so the check runs with none. A
# stock Mac's /usr/bin/ruby (Ruby 2.6) stays: /usr/bin holds everything else.
clean=""
IFS=: read -ra dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  if [ "$d" != /usr/bin ] && { [ -e "$d/ruby" ] || [ -e "$d/ruby.exe" ]; }; then
    echo "== dropped from PATH (holds a ruby): $d"
  else
    clean="${clean:+$clean:}$d"
  fi
done
export PATH="$clean"

work="$(mktemp -d "${TMPDIR:-/tmp}/install-check.XXXXXX")"
export MISE_DATA_DIR="$work/data" MISE_CACHE_DIR="$work/cache" MISE_STATE_DIR="$work/state" \
  MISE_CONFIG_DIR="$work/config" MISE_GLOBAL_CONFIG_FILE="$work/config/config.toml" \
  MISE_TRUSTED_CONFIG_PATHS="$work"
mkdir -p "$work/proj" "$work/config"
cat > "$work/config/config.toml" <<EOF
[tools]
node = "22"
jq = "1.7"

[tools."http:crosslint-spike"]
version = "0.0.1"
url = "$url"
$(printf '%s\n' "$opts" | tr ',' '\n')
EOF

echo "== mise $(mise --version)"
echo "== ruby on PATH before: $(command -v ruby || echo none)"
cd "$work/proj" || exit 1

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
elapsed() { perl -e "printf '%.2f', $2 - $1"; }

start=$(now)
mise install 2>&1 | tail -5
echo "== install seconds (the app, Node and jq): $(elapsed "$start" "$(now)")"

install_dir="$(mise where http:crosslint-spike 2>/dev/null)"
echo "== install dir: $install_dir"
echo "== installed size KiB: $(du -sk "$install_dir" | cut -f1)"
echo "== files at top of install dir: $(ls "$install_dir" | tr '\n' ' ')"
echo "== mise which crosslint-spike: $(mise which "$exe" 2>&1)"
echo "== ruby on PATH under mise x: $(mise x -- bash -c 'command -v ruby' 2>&1 || echo none)"

tool="$(mise which "$exe")"
s=$(now); "$tool" --info >/dev/null 2>&1; echo "== first run seconds: $(elapsed "$s" "$(now)")"
s=$(now); for _ in 1 2 3 4 5 6 7 8 9 10; do "$tool" --info >/dev/null 2>&1; done
echo "== mean seconds of 10 later runs: $(elapsed "$s" "$(now)" | perl -ne 'printf "%.3f", $_/10')"
echo "== --info"
mise x -- crosslint-spike --info 2>&1

# run.sh, against the installed app. It copies nothing into the repository's folder.
cp -R "$here/.." "$work/plugin-protocol"
rm -rf "$work/plugin-protocol/fledge"
cd "$work/plugin-protocol" || exit 1
echo "== run.sh with CROSSLINT=crosslint-spike"
mise x -- env CROSSLINT=crosslint-spike bash run.sh 2>&1
status=$?
echo "== run.sh exit: $status"
echo "== work folder: $work"
exit "$status"
