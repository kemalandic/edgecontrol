#!/usr/bin/env bash
# The commands CI runs. The workflow calls this file, so what you run locally and
# what runs on a pull request cannot drift apart.
#
#   Scripts/ci-local.sh [build|test|all]
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=EdgeControl.xcodeproj
SCHEME=EdgeControl
DEST='platform=macOS'
RESULT_BUNDLE="${RESULT_BUNDLE:-TestResults.xcresult}"

# A hosted runner holds no signing identity for this team. Forcing the same
# unsigned configuration locally is what stops "builds on my Mac" from hiding a
# CI failure — this machine does have the team certificate installed.
UNSIGNED=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=""
    DEVELOPMENT_TEAM=""
)

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

generate() {
    step "xcodegen generate"
    xcodegen generate
}

# Warnings are counted, not fatal — a ratchet, so new work cannot add to the pile
# while the existing ones are worked off. Lower it whenever the count drops;
# raise it only when a toolchain moves under us, never to make a new warning go
# away.
#
# Zero, and it should stay there. Raise it only when a toolchain moves under us,
# never to make a new warning go away — a warning that earns a raise is a
# warning worth reading first.
WARN_BUDGET="${WARN_BUDGET:-0}"

build() {
    # A runner always starts from an empty derived-data directory, so its build is
    # always clean. An incremental local build re-emits no warnings for files it
    # did not recompile, which silently reports zero — set SKIP_CLEAN=1 only when
    # iterating and you do not care about the warning count.
    # build-for-testing, not build: the app scheme's build action covers only
    # EdgeControl.app, so warnings in the test target were never counted.
    local action="clean build-for-testing"
    [ "${SKIP_CLEAN:-0}" = "1" ] && action="build-for-testing"

    step "build — unsigned ($action)"
    local log
    log=$(mktemp)
    # shellcheck disable=SC2086
    if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration Debug -destination "$DEST" \
        "${UNSIGNED[@]}" \
        $action 2>&1 | tee "$log"; then
        rm -f "$log"
        return 1
    fi

    # Count what is displayed, not raw log lines: xcodebuild emits the same
    # file-level warning from more than one job, and counting rows the reader
    # cannot see turns a clean build into an unexplained failure.
    #
    # Every pipeline here ends in `|| true`. Under `set -o pipefail` a grep that
    # matches nothing exits 1, which errexit would turn into a failed build at
    # exactly the moment the warning count reaches zero.
    local warnings count
    warnings=$(grep -E '^/.*warning: ' "$log" \
        | sed -E 's|^.*/([^/]+\.swift):([0-9]+):[0-9]+: warning: |  \1:\2  |' \
        | sed -E 's/ \[#[A-Za-z]+\]$//' \
        | sort -u || true)
    rm -f "$log"

    if [ -z "$warnings" ]; then count=0; else count=$(printf '%s\n' "$warnings" | wc -l | tr -d ' '); fi
    echo
    echo "Compiler warnings: $count (budget $WARN_BUDGET)"
    if [ -n "$warnings" ]; then printf '%s\n' "$warnings"; fi

    if [ "$count" -gt "$WARN_BUDGET" ]; then
        echo "New warnings introduced — budget is $WARN_BUDGET, saw $count." >&2
        return 1
    fi

    # Explicit: without it the function inherits the exit status of the test
    # above, which is 1 whenever the count is within budget.
    return 0
}

run_tests() {
    step "test"
    rm -rf "$RESULT_BUNDLE"
    # test-without-building: build() already produced the test bundle with
    # build-for-testing, so this runs it instead of compiling everything twice.
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration Debug -destination "$DEST" \
        "${UNSIGNED[@]}" \
        -enableCodeCoverage YES \
        -resultBundlePath "$RESULT_BUNDLE" \
        test-without-building
}

coverage() {
    step "coverage"
    if [ -d "$RESULT_BUNDLE" ]; then
        xcrun xccov view --report --only-targets "$RESULT_BUNDLE"
    else
        echo "No result bundle at $RESULT_BUNDLE."
    fi
}

case "${1:-all}" in
    build) generate; build ;;
    test)  generate; build; run_tests; coverage ;;
    all)   generate; build; run_tests; coverage ;;
    *)     echo "usage: $0 [build|test|all]" >&2; exit 2 ;;
esac
