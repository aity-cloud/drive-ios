#!/usr/bin/env bash
#
# materialize.sh - produce the buildable Aity Drive iOS tree from the Pin.
#
#   scripts/materialize.sh <production|staging> [--check]
#
# What it does (ADR 0001 - overlay factory, never a fork):
#   1. clone owncloud/ios-app at the Pin (UPSTREAM_TAG) into build/upstream
#      and check out the ios-sdk submodule at the commit the Pin records
#   2. copy overlay/common/ over the tree, then overlay/<env>/ over that
#   3. copy the factory's fastlane/ files and Gemfile over upstream's
#      (build recipe; upstream's branding flow is transcribed there)
#   4. apply patches/*.patch (target: zero patches, see PATCHES.md)
#   5. record the environment in build/upstream/.aity-environment for the
#      fastlane lanes
#
# --check: after materialising, verify every overlay/recipe file lands on a
# path upstream actually has (replaced files must exist upstream; new files
# need an existing parent directory). This is the Bump tripwire: it fails
# when upstream moves or renames the paths the Overlay relies on. Used by
# the Linux `lint` CI job; needs network for the clone, no Xcode.
#
# The same script is used by CI and by a developer. Idempotent: an existing
# clone at the right tag is reused; overlay copies just overwrite.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/owncloud/ios-app.git}"
BUILD_DIR="${REPO_ROOT}/build"
TREE="${BUILD_DIR}/upstream"

# The Pin. CI exports UPSTREAM_TAG from .gitlab-ci.yml; for local runs the
# default below is parsed out of .gitlab-ci.yml so there is a single source
# of truth.
if [ -z "${UPSTREAM_TAG:-}" ]; then
    UPSTREAM_TAG="$(sed -n 's/^[[:space:]]*UPSTREAM_TAG:[[:space:]]*"\{0,1\}\([^" ]*\)"\{0,1\}[[:space:]]*$/\1/p' "${REPO_ROOT}/.gitlab-ci.yml" | head -n 1)"
fi
if [ -z "${UPSTREAM_TAG}" ]; then
    echo "materialize: could not determine UPSTREAM_TAG (env or .gitlab-ci.yml)" >&2
    exit 1
fi

usage() {
    echo "usage: scripts/materialize.sh <production|staging> [--check]" >&2
    exit 2
}

ENVIRONMENT="${1:-}"
MODE="${2:-}"
case "${ENVIRONMENT}" in
    production|staging) ;;
    *) usage ;;
esac
case "${MODE}" in
    ""|--check) ;;
    *) usage ;;
esac

echo "materialize: Pin ${UPSTREAM_TAG}, environment ${ENVIRONMENT}${MODE:+, mode ${MODE}}"

# --- 1. clone the Pin -------------------------------------------------------

if [ -d "${TREE}/.git" ]; then
    CURRENT_TAG="$(git -C "${TREE}" describe --tags --exact-match 2>/dev/null || true)"
    if [ "${CURRENT_TAG}" != "${UPSTREAM_TAG}" ]; then
        echo "materialize: existing clone is at '${CURRENT_TAG:-unknown}', want ${UPSTREAM_TAG} - recloning"
        rm -rf "${TREE}"
    fi
fi

if [ ! -d "${TREE}/.git" ]; then
    mkdir -p "${BUILD_DIR}"
    git clone --depth 1 --branch "${UPSTREAM_TAG}" "${UPSTREAM_REPO}" "${TREE}"
else
    # Reused clone: drop any previous overlay/patch state so every run
    # starts from the pristine Pin.
    git -C "${TREE}" checkout -- .
    git -C "${TREE}" clean -fd --quiet
fi

# ios-sdk submodule at the commit the Pin records (not a branch, not a tag
# of its own - the app tag is the only thing Renovate bumps; the submodule
# pin follows it).
git -C "${TREE}" submodule update --init --depth 1 ios-sdk
SDK_COMMIT="$(git -C "${TREE}" submodule status ios-sdk | awk '{print $1}' | tr -d '+-')"
echo "materialize: ios-sdk submodule at ${SDK_COMMIT}"

# --- 2+3. lay the overlay and the recipe ------------------------------------

overlay_sources() {
    # Every file we place into the tree, one "src|dst" pair per line.
    # Order matters: common first, then the environment, then the recipe.
    local src rel
    for layer in "overlay/common" "overlay/${ENVIRONMENT}"; do
        [ -d "${REPO_ROOT}/${layer}" ] || continue
        while IFS= read -r src; do
            rel="${src#"${REPO_ROOT}/${layer}/"}"
            printf '%s|%s\n' "${src}" "${rel}"
        done < <(find "${REPO_ROOT}/${layer}" -type f ! -name '.gitkeep' | sort)
    done
    # The build recipe: our fastlane lanes and Gemfile replace upstream's.
    while IFS= read -r src; do
        rel="fastlane/${src#"${REPO_ROOT}/fastlane/"}"
        printf '%s|%s\n' "${src}" "${rel}"
    done < <(find "${REPO_ROOT}/fastlane" -type f ! -name 'report.xml' ! -name 'README.md' ! -path '*/test_output/*' | sort)
    printf '%s|%s\n' "${REPO_ROOT}/Gemfile" "Gemfile"
    printf '%s|%s\n' "${REPO_ROOT}/Gemfile.lock" "Gemfile.lock"
}

CHECK_FAILED=0
while IFS='|' read -r src rel; do
    dst="${TREE}/${rel}"
    if [ "${MODE}" = "--check" ]; then
        # Replacement: the file must exist upstream. New file: its parent
        # directory must exist upstream (a missing parent means upstream
        # moved the mechanism this Overlay hooks into).
        parent="$(dirname "${rel}")"
        if git -C "${TREE}" cat-file -e "HEAD:${rel}" 2>/dev/null; then
            echo "check: replaces upstream file   ${rel}"
        elif [ "${parent}" = "." ] || git -C "${TREE}" cat-file -e "HEAD:${parent}" 2>/dev/null; then
            echo "check: new file in upstream dir ${rel}"
        else
            echo "check: FAIL - neither '${rel}' nor its directory exist in ${UPSTREAM_TAG}" >&2
            CHECK_FAILED=1
        fi
    fi
    mkdir -p "$(dirname "${dst}")"
    cp "${src}" "${dst}"
done < <(overlay_sources)

if [ "${MODE}" = "--check" ] && [ "${CHECK_FAILED}" -ne 0 ]; then
    echo "materialize: --check failed - the Overlay no longer matches the upstream tree at ${UPSTREAM_TAG}" >&2
    exit 1
fi

# --- 4. patches -------------------------------------------------------------

shopt -s nullglob
PATCHES=("${REPO_ROOT}/patches/"*.patch)
shopt -u nullglob
if [ "${#PATCHES[@]}" -eq 0 ]; then
    echo "materialize: no patches to apply (the target state)"
else
    for patch in "${PATCHES[@]}"; do
        echo "materialize: applying $(basename "${patch}")"
        git -C "${TREE}" apply --verbose "${patch}"
    done
fi

# --- 5. environment marker --------------------------------------------------

printf '%s\n' "${ENVIRONMENT}" > "${TREE}/.aity-environment"

echo "materialize: done - ${TREE} is the ${ENVIRONMENT} tree at ${UPSTREAM_TAG} (sdk ${SDK_COMMIT})"
