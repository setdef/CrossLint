#!/usr/bin/env bash
# Debt tracking under design (a), the host does it, and design (b), a plugin does it through the
# post_check hook, over the same cases. Each case copies the fixture plus debt/overlay into
# .scratch/debt/proj, puts debt/cases/NAME.tsv there as the debt file, runs the host with
# debt/cases/NAME.json as the config and debt/cases/NAME.flags as extra host flags, and compares the
# output and exit status with debt/expected/NAME.out, and the debt file afterward with
# debt/expected/NAME.tsv when that exists. Both designs must give the same results.
# Usage: check.sh CASE...   Called by ../run.sh, and needs the same tools.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
d="$here/debt"
proj="$here/.scratch/debt/proj"
out="$here/.scratch/debt"
if [ -n "${CROSSLINT:-}" ]; then host_cmd=("$CROSSLINT"); else host_cmd=(ruby "$here/host/crosslint.rb"); fi
failed=0
mkdir -p "$out"

# run_case NAME DESIGN TSV: leaves the output in .scratch/debt/NAME.DESIGN.out (and .tsv, the debt file afterward).
run_case() {
  local name="$1" design="$2" tsv="$3" status=0 cfg="$d/cases/none.json" flags=() plugins=("$here/plugins/ng-nudge-rules-rb" "$here/plugins/ng-nudge-ts-js") env_cmd=(env)
  rm -rf "$proj"
  mkdir -p "$proj"
  cp -R "$here/fixture/src" "$here/fixture/.config" "$here/fixture/tsconfig.json" "$here/fixture/package.json" "$proj/"
  cp -R "$d/overlay/." "$proj/"
  ln -s "$here/fixture/node_modules" "$proj/node_modules"
  if [ -f "$d/cases/$tsv.tsv" ]; then cp "$d/cases/$tsv.tsv" "$proj/.config/ng-nudge/debt.tsv"; else rm -f "$proj/.config/ng-nudge/debt.tsv"; fi
  [ -f "$d/cases/$name.json" ] && cfg="$d/cases/$name.json"
  [ -f "$d/cases/$name.flags" ] && read -ra flags <"$d/cases/$name.flags"
  # A case named *-no-node runs with no node on PATH, so the TypeScript plugin fails.
  if [[ "$name" == *-no-node ]]; then env_cmd=(env "PATH=$(dirname "$(command -v "${host_cmd[0]}")"):/usr/bin:/bin"); fi
  if [ "$design" = a ]; then flags+=(--core-debt); else plugins+=("$here/plugins/debt-rb"); fi
  # A case with a .hooks file also runs a second post_check plugin, after debt tracking in both designs.
  [ -f "$d/cases/$name.hooks" ] && plugins+=("$here/plugins/summary-sh")
  "${env_cmd[@]}" "${host_cmd[@]}" --root "$proj" --config "$cfg" ${flags[@]+"${flags[@]}"} "${plugins[@]}" >"$out/$name.$design.out" 2>"$out/$name.$design.err" || status=$?
  echo "exit $status" >>"$out/$name.$design.out"
  if [ -f "$proj/.config/ng-nudge/debt.tsv" ]; then cp "$proj/.config/ng-nudge/debt.tsv" "$out/$name.$design.tsv"; else rm -f "$out/$name.$design.tsv"; fi
}

for arg in "$@"; do
  name="${arg%%=*}"
  tsv="${arg#*=}" # NAME=OTHER starts case NAME from the debt file of case OTHER
  ok=1
  for design in a b; do
    run_case "$name" "$design" "$tsv"
    # BLESS=1 writes design (a)'s results as the expected files; read them before you commit them.
    if [ -n "${BLESS:-}" ] && [ "$design" = a ]; then
      cp "$out/$name.a.out" "$d/expected/$name.out"
      if [ -f "$d/cases/$name.flags" ]; then cp "$out/$name.a.tsv" "$d/expected/$name.tsv"; fi
    fi
    diff -u "$d/expected/$name.out" "$out/$name.$design.out" || ok=0
    if [ -f "$d/expected/$name.tsv" ]; then diff -u "$d/expected/$name.tsv" "$out/$name.$design.tsv" || ok=0; fi
  done
  if [ "$ok" = 1 ]; then echo "ok   debt, designs a and b: $name"; else echo "FAIL debt: $name"; failed=1; fi
done
exit "$failed"
