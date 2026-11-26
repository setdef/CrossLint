#!/bin/sh
# Installs the gem and compiles the TypeScript and TSX grammars into build/.
# Needs: ruby with bundler, a C compiler, curl, tar, and shasum or sha256sum.
set -eu
cd "$(dirname "$0")"

VERSION=0.23.2
SHA256=2c4ce711ae8d1218a3b2f899189298159d672870b5b34dff5d937bed2f3e8983
URL="https://codeload.github.com/tree-sitter/tree-sitter-typescript/tar.gz/refs/tags/v$VERSION"

bundle config set --local path vendor/bundle
bundle install --quiet

mkdir -p build
if [ ! -f build/grammar.tgz ]; then
  curl -fsSL "$URL" -o build/grammar.tgz
fi
if command -v sha256sum >/dev/null 2>&1; then
  echo "$SHA256  build/grammar.tgz" | sha256sum -c - >/dev/null
else
  echo "$SHA256  build/grammar.tgz" | shasum -a 256 -c - >/dev/null
fi
tar xzf build/grammar.tgz -C build

case "$(uname -s)" in
  Darwin) EXT=dylib ;;
  MINGW*|MSYS*) EXT=dll ;;
  *) EXT=so ;;
esac

for LANG in typescript tsx; do
  SRC="build/tree-sitter-typescript-$VERSION/$LANG/src"
  cc -shared -fPIC -O1 -I "$SRC" -o "build/libtree-sitter-$LANG.$EXT" "$SRC/parser.c" "$SRC/scanner.c"
done
ls build/*.$EXT
