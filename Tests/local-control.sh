#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d -t conductor-control-tests)"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -framework AppKit "$project/Sources/LocalControl.swift" "$project/Tests/LocalControlTests.swift" -o "$scratch/local-control-tests"
"$scratch/local-control-tests"
