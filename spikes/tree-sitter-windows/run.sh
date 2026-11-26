#!/usr/bin/env bash

# Builds each variant of ruby_tree_sitter and runs repro.rb with it in three
# modes. Needs mise, a C compiler and make; mise installs the Ruby.
#
#   MISE_ENV=head bash run.sh                   # default variants for this system
#   MISE_ENV=ruby40 bash run.sh spike fix       # chosen variants
#
# Variants: stock (as published; macOS and Linux only), ulong (Windows: compile
# changes only), spike (Windows: compile changes and ULL2NUM, as in
# ../fledge-tree-sitter), and fix (the changes above plus patches/free-deferred.patch).
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

for config in mise.toml mise.head.toml mise.ruby40.toml; do
  mise trust -q "$config"
done
mise install
mise x -- ruby -v

# The gems ruby_tree_sitter requires, in a folder of their own for this Ruby.
GEM_HOME="$here/build/gems-${MISE_ENV:-default}"
GEM_PATH="$GEM_HOME"
export GEM_HOME GEM_PATH
mise x -- gem install --no-document oppen sorbet-runtime zeitwerk

case "$(uname -s)" in
  MINGW*|MSYS*) windows=1; ext=dll; default="ulong spike fix" ;;
  Darwin) windows=0; ext=dylib; default="stock fix" ;;
  *) windows=0; ext=so; default="stock fix" ;;
esac
variants="${*:-$default}"

summary=""
for v in $variants; do
  case "$v" in
    stock|spike) flags="" ;;
    ulong) flags="--ulong" ;;
    fix) flags="--fix" ;;
    *) echo "unknown variant $v"; exit 2 ;;
  esac
  if ! mise x -- ruby build.rb "$v" $flags; then
    summary="$summary
$v: build failed"
    continue
  fi
  for mode in exit gc keep many; do
    echo "=== $v $mode"
    mise x -- ruby -I "build/$v/gem/lib" repro.rb "build/$v/libtree-sitter-json.$ext" "$mode"
    status=$?
    echo "=== $v $mode: exit status $status"
    summary="$summary
$v $mode: $status"
  done
done
echo
echo "SUMMARY (MISE_ENV=${MISE_ENV:-none})$summary"
