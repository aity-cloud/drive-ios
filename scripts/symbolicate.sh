#!/usr/bin/env bash
# Symbolicate crash-report frames against the dSYM of a shipped build.
#
# A device crash report gives you an image UUID and byte offsets, and that is
# all: the shipped binary is stripped, so resolving offsets against it lands
# on whatever helper symbol happens to precede them (measured: "+27952 from
# _block_destroy_helper", i.e. useless). The dSYM has the real thing.
#
# Usage:
#   scripts/symbolicate.sh <image-uuid> <offset> [offset...]
#
# Example, from the .ips of build 21 (ownCloudAppShared):
#   scripts/symbolicate.sh ecec073b-1c32-361a-821f-362413216a0c 272868 735024
#
# It searches Xcode's Archives and this Factory's DerivedData for a dSYM whose
# UUID matches - matching by UUID, never by name, because several builds of
# the same framework are on the runner and picking the wrong one produces
# confident nonsense.
set -euo pipefail

UUID="${1:?usage: symbolicate.sh <image-uuid> <offset> [offset...]}"
shift
[ "$#" -gt 0 ] || { echo "no offsets given"; exit 2; }

SEARCH_DIRS=(
  "$HOME/Library/Developer/Xcode/Archives"
  "$HOME/Library/Developer/Xcode/DerivedData"
  "$(cd "$(dirname "$0")/.." && pwd)/build"
)

echo "looking for a dSYM with UUID $UUID"
MATCH=""
while IFS= read -r dsym; do
  # dwarfdump prints: UUID: <uuid> (arch) <path>
  if dwarfdump --uuid "$dsym" 2>/dev/null | grep -qi "$UUID"; then
    MATCH="$dsym"
    break
  fi
done < <(find "${SEARCH_DIRS[@]}" -name '*.dSYM' -maxdepth 6 2>/dev/null)

if [ -z "$MATCH" ]; then
  echo "NO dSYM with that UUID on this runner."
  echo "The archive may have been cleaned, or the build came from a different machine."
  echo "Rebuild the same commit and keep its dSYM, or re-run with a UUID from a build that is still here:"
  find "${SEARCH_DIRS[@]}" -name '*.dSYM' -maxdepth 6 2>/dev/null | head -20
  exit 1
fi

echo "dSYM: $MATCH"
BIN="$(find "$MATCH/Contents/Resources/DWARF" -type f | head -1)"
echo "DWARF: $BIN"
echo

# atos wants a load address; the offsets from the report are relative to the
# image base, so use 0 and let each offset be the address.
# Offsets from a crash report are DECIMAL; atos reads a bare digit string as
# HEX, so 272868 became 0x272868 and every frame resolved to nonsense (or to
# nothing). Convert explicitly - this cost one wrong diagnosis on 2026-08-27.
for off in "$@"; do
  hex=$(printf '0x%x' "$off")
  printf '  +%-9s (%s)  %s\n' "$off" "$hex" "$(atos -o "$BIN" -arch arm64 -l 0 "$hex" 2>/dev/null || echo '(atos failed)')"
done
