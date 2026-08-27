#!/usr/bin/env bash
# Type-check the XCUITest smoke sources on a machine that has no Xcode.
#
#   scripts/check-smoke-swift.sh
#
# `swiftc -parse` only parses; it never resolves a name, so a call to a helper
# that no longer exists compiles clean locally and fails on the Mac. That is a
# full round trip on Raul's laptop for a typo. This compiles the smoke sources
# together with smoke/typecheck/XCTestStubs.swift (hand-written stand-ins for
# XCTest and XCUITest, which have no Linux implementation) using
# `swiftc -typecheck`, so undefined names, wrong arity and wrong types are
# caught before anything is pushed.
#
# It is NOT an API-compatibility check - the stubs are hand-written and can
# drift from Apple's real signatures. Green here means "worth sending to the
# Mac", never "this will pass". Read the header of XCTestStubs.swift.
#
# Uses a local `swiftc` when there is one (a Mac has one), and falls back to
# the official Swift container.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCES=(smoke/typecheck/XCTestStubs.swift smoke/AityDriveSmokeUITests/*.swift)
IMAGE="${AITY_SWIFT_IMAGE:-swift:6.1}"

if command -v swiftc >/dev/null 2>&1 && [ "$(uname -s)" != "Darwin" ]; then
    echo "==> swiftc -typecheck (local toolchain)"
    swiftc -typecheck "${SOURCES[@]}"
elif command -v docker >/dev/null 2>&1; then
    echo "==> swiftc -typecheck (container $IMAGE)"
    docker run --rm -v "$ROOT:/w" -w /w "$IMAGE" swiftc -typecheck "${SOURCES[@]}"
else
    echo "check-smoke-swift: no swiftc and no docker - skipping" >&2
    echo "(on macOS the real SDK is used by xcodebuild anyway)" >&2
    exit 0
fi

echo "check-smoke-swift: OK - every name in the smoke sources resolves"
