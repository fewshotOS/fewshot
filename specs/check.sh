#!/usr/bin/env bash
# Runs every R0 check: TLC on the TLA+ specs, Verus on the Rust proofs.
# Tools are downloaded once into .tools/ at pinned versions with checksums.
#
#   specs/check.sh          # both
#   specs/check.sh tla      # TLA+ only
#   specs/check.sh verus    # Verus only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools"
mkdir -p "$TOOLS"

TLA_VERSION="1.8.0"
TLA_SHA256="15d103b7e5617780bcc904c0af12f1ad242e2b345c0301136c5be4588f17edac"
VERUS_VERSION="0.2026.09.27.3cf1832"
VERUS_SHA256="43814031e10df043221d83c7fa842e3ebd662cb7b0090fc1eb4d7a8673226978"
VERUS_TOOLCHAIN="1.98.1-x86_64-unknown-linux-gnu"

fetch() { # url dest sha256
  if [[ ! -f "$2" ]]; then
    curl -fsSL -o "$2.part" "$1"
    echo "$3  $2.part" | sha256sum -c --quiet
    mv "$2.part" "$2"
  fi
}

run_tla() {
  local jar="$TOOLS/tla2tools-$TLA_VERSION.jar"
  fetch "https://github.com/tlaplus/tlaplus/releases/download/v$TLA_VERSION/tla2tools.jar" "$jar" "$TLA_SHA256"
  local out
  for spec in "$ROOT"/specs/tla/*.tla; do
    echo "== TLC: $(basename "$spec")"
    out="$(java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto -deadlock \
      -metadir "$TOOLS/tlc-states" -config "${spec%.tla}.cfg" "$spec" 2>&1)" || true
    echo "$out" | grep -E "states generated|distinct states|Error|violated|No error" || true
    grep -q "No error has been found" <<<"$out" || { echo "$out" | tail -60; return 1; }
  done
}

run_verus() {
  local dir="$TOOLS/verus-$VERUS_VERSION"
  if [[ ! -x "$dir/verus-x86-linux/verus" ]]; then
    fetch "https://github.com/verus-lang/verus/releases/download/release/$VERUS_VERSION/verus-$VERUS_VERSION-x86-linux.zip" \
      "$TOOLS/verus-$VERUS_VERSION.zip" "$VERUS_SHA256"
    mkdir -p "$dir" && unzip -q "$TOOLS/verus-$VERUS_VERSION.zip" -d "$dir"
    rm "$TOOLS/verus-$VERUS_VERSION.zip"
  fi
  rustup toolchain list | grep -q "^$VERUS_TOOLCHAIN" || rustup install "$VERUS_TOOLCHAIN" --profile minimal
  echo "== Verus: specs/verus/main.rs"
  "$dir/verus-x86-linux/verus" "$ROOT/specs/verus/main.rs"
}

case "${1:-all}" in
  tla) run_tla ;;
  verus) run_verus ;;
  all) run_tla && run_verus ;;
  *) echo "usage: $0 [tla|verus|all]" >&2; exit 2 ;;
esac
