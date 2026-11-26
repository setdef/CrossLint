#!/usr/bin/env bash
# Reruns the spike: three plugins on the fixture, then every error path.
# Needs ruby (3.2+), node (20+), jq, and network access the first time (npm installs typescript 6.0.3 into fixture/).
# Exits 0 when every result matches. Pass TIMING=1 to print per-plugin timings.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
host=("ruby" "$here/host/crosslint.rb" "--root" "$here/fixture")
[ -n "${TIMING:-}" ] && host+=("--timing")
failed=0
mkdir -p "$here/.scratch"

if [ ! -d "$here/fixture/node_modules/typescript" ]; then
  npm --prefix "$here/fixture" install --no-audit --no-fund --package-lock=false >/dev/null
fi

ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; failed=1; }

# 1. Three plugins, in three languages, one fixture project.
status=0
"${host[@]}" "$here/plugins/spec-per-component-rb" "$here/plugins/template-per-component-sh" "$here/plugins/component-io-js" >"$here/.scratch/out.txt" || status=$?
if [ "$status" = 1 ] && diff -u "$here/expected/violations.txt" "$here/.scratch/out.txt"; then ok "three plugins give the expected violations (exit 1)"; else bad "three plugins (status $status)"; fi

# 2. Error paths: each must exit 2 and name the plugin and the kind of failure.
expect_failure() { # dir expected-substring
  local err status=0
  err="$("${host[@]}" "$here/plugins-broken/$1" 2>&1 >/dev/null)" || status=$?
  if [ "$status" = 2 ] && [[ "$err" == *"$2"* ]]; then ok "$1: $2"; else bad "$1: status $status, stderr: $err"; fi
}
expect_failure missing-runtime "needs-a-runtime-nobody-has: runtime-missing: needs crosslint-no-such-runtime on PATH"
expect_failure missing-helper "needs-a-helper-tool: runtime-missing: needs crosslint-no-such-tool on PATH"
expect_failure too-old "needs-node-99: runtime-too-old"
expect_failure crash "crashes: exited: status 3 before answering. stderr: boom"
expect_failure garbage "prints-garbage: bad-json"
expect_failure wrong-protocol "speaks-protocol-2: protocol-mismatch"
expect_failure error-reply "replies-with-an-error: dependency-missing"
export HANG_PIDFILE="$here/.scratch/hang.pid"
rm -f "$HANG_PIDFILE"
expect_failure hang "hangs: timeout: no answer to handshake in 2 s"

# The hung plugin started a child (sleep 30). After the timeout the host must have ended it too.
child="$(cat "$HANG_PIDFILE" 2>/dev/null || true)"
left=yes
if [ -n "$child" ]; then
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$child" 2>/dev/null || { left=no; break; }
    sleep 0.2
  done
fi
if [ -z "$child" ]; then bad "hang: the plugin did not record its child's pid"
elif [ "$left" = no ]; then ok "hang: the plugin's child (pid $child) is gone after the timeout"
else bad "hang: the plugin's child (pid $child) is still running"; kill "$child" 2>/dev/null || true; fi

# A real plugin reporting an error: the project it runs in has no typescript.
status=0
err="$(ruby "$here/host/crosslint.rb" --root "$here/plugins-broken" "$here/plugins/component-io-js" 2>&1 >/dev/null)" || status=$?
if [ "$status" = 2 ] && [[ "$err" == *"component-io: dependency-missing"* ]]; then ok "component-io: dependency-missing"; else bad "component-io without typescript: $status $err"; fi

# 3. Missing runtime, found by name while the other plugins still run: PATH has ruby and the system tools, no node.
ruby_dir="$(dirname "$(command -v ruby)")"
status=0
err="$(env PATH="$ruby_dir:/usr/bin:/bin" ruby "$here/host/crosslint.rb" --root "$here/fixture" "$here/plugins/component-io-js" "$here/plugins/spec-per-component-rb" 2>&1 >/dev/null)" || status=$?
if ! PATH="$ruby_dir:/usr/bin:/bin" command -v node >/dev/null 2>&1; then
  if [ "$status" = 2 ] && [[ "$err" == *"component-io: runtime-missing: needs node on PATH"* ]]; then ok "no node on PATH: named, exit 2, other plugin still ran"; else bad "no node on PATH: $status $err"; fi
else
  echo "skip no-node check: node is in /usr/bin or /bin here"
fi

exit "$failed"
