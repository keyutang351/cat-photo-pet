#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
build="$(mktemp -d "${TMPDIR:-/tmp}/cat-wand.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
xcrun swiftc -module-cache-path "$build/modules" CatWand.swift -o "$build/CatWand"
"$build/CatWand" "$@"
