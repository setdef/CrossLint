#!/bin/bash
# Throwaway evidence for README section "Installing a plugin through mise".
# Packs a data-only plugin into a tarball, installs it with mise's `http:` backend
# from a file:// URL, then repeats with a GitHub tag archive URL (no release needed).
# Everything lives under $WORK; mise gets its own data, cache and config dirs so no
# global state is touched. Usage: try-mise.sh WORKDIR
set -eu
WORK=${1:?usage: try-mise.sh WORKDIR}
rm -rf "$WORK"; mkdir -p "$WORK"/{src/example-plugin/rules,project,archives,mise/{data,cache,config,state}}
cd "$WORK"
export MISE_DATA_DIR=$PWD/mise/data MISE_CACHE_DIR=$PWD/mise/cache MISE_CONFIG_DIR=$PWD/mise/config MISE_STATE_DIR=$PWD/mise/state
export MISE_TRUSTED_CONFIG_PATHS=$PWD/project MISE_LOCKFILE=1 MISE_YES=1

cat > src/example-plugin/crosslint-plugin.yml <<'EOF'
# Example data-only plugin: one artifact kind and one rule, no code in any language.
name: example-plugin
artifacts:
  - role: "docs/*.md"
    companions: { index: "docs/README.md" }
EOF
echo "# rule sketch" > src/example-plugin/rules/rule-sketch.yml
tar -czf archives/example-plugin-0.1.0.tar.gz -C src example-plugin
SUM=$(shasum -a 256 archives/example-plugin-0.1.0.tar.gz | cut -d' ' -f1)

echo "== 1. data-only plugin from a file:// archive, pinned by checksum"
cat > project/mise.toml <<EOF
[tools]
"http:crosslint-plugin-example-plugin" = { version = "0.1.0", url = "file://$PWD/archives/example-plugin-0.1.0.tar.gz", checksum = "sha256:$SUM" }
EOF
(cd project && touch mise.lock && mise install 2>&1 | tail -5 && echo "-- where:" && mise where "http:crosslint-plugin-example-plugin" && echo "-- files:" && find "$(mise where 'http:crosslint-plugin-example-plugin')" -type f | sed "s|$PWD/||" && echo "-- mise.lock (first 12 lines):" && mise lock >/dev/null 2>&1; head -12 mise.lock)

echo "== 2. tampered archive is refused"
cp archives/example-plugin-0.1.0.tar.gz archives/good.tgz
echo x >> src/example-plugin/rules/rule-sketch.yml
tar -czf archives/example-plugin-0.1.0.tar.gz -C src example-plugin
(cd project && MISE_DATA_DIR=$PWD/../mise/data2 mise install 2>&1 | tail -4 || true)
cp archives/good.tgz archives/example-plugin-0.1.0.tar.gz

echo "== 3. a GitHub tag archive (a tag, no release) as the plugin source"
cat > project/mise.toml <<'EOF'
[tools]
"http:crosslint-plugin-example" = { version = "0.7.1", url = "https://github.com/rubocop/rubocop-rake/archive/refs/tags/v0.7.1.tar.gz" }
EOF
rm -f project/mise.lock
(cd project && touch mise.lock && mise install 2>&1 | tail -4 && ls "$(mise where 'http:crosslint-plugin-example')" | head -8 && mise lock >/dev/null 2>&1; grep -m2 -E 'checksum|url' mise.lock)
