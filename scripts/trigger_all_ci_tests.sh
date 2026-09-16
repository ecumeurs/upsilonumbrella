#!/bin/bash
cd "$(dirname "$0")/.."
# trigger_all_tests.sh - Run all E2E and Edge Case tests locally

set -e

# 1. Pre-flight Check
if [ ! -f "./scripts/check_services.sh" ]; then
    echo "ERROR: scripts/check_services.sh not found."
    exit 1
fi

echo "Checking local services..."
if ! ./scripts/check_services.sh; then
    echo "ERROR: Some services are down. Please start the stack before running tests."
    exit 1
fi

# 2. Build CLI (always rebuild: bin/ is git-ignored, a stale binary would
#    silently test code that is not the working tree)
CLI="./upsiloncli/bin/upsiloncli"
if ! CLI_BUILD_OUTPUT=$(cd upsiloncli && go build -o bin/upsiloncli cmd/upsiloncli/main.go 2>&1); then
    echo "ERROR: Failed to build upsiloncli CLI:"
    echo "$CLI_BUILD_OUTPUT"
    exit 1
fi

# 3. Execution Setup
SCENARIO_DIR="upsiloncli/tests/scenarios"
LOG_DIR="upsiloncli/tests/logs"
mkdir -p "$LOG_DIR"

echo "=================================================="
echo "      UPSILON LOCAL TEST TRIGGER (E2E + EDGE)"
echo "=================================================="

# 0. Purge stale data and seed database
echo "Resetting and seeding database..."
./scripts/seed_ci.sh


FAILED_TESTS=""
PASSED_COUNT=0
FAILED_COUNT=0
TOTAL_START_TIME=$SECONDS

# Extract a one-line failure reason per bot log for the given scenario.
# Strategy:
#   - first JS Exception / Assertion Failed line is the primary reason
#   - if that reason is opaque ("[object Object]"), surface the most recent
#     CALL_ERROR before it (typically the 4xx/5xx that the JS code didn't unwrap)
#   - if no JS Exception at all, fall back to the last CALL_ERROR / REPLY 4xx/5xx
#   - strip ANSI color codes and the "[{ts}] [Bot-NN] " prefix
print_failure_reasons() {
    local name=$1
    local found=0
    for bot_log in "$LOG_DIR/${name}"_Bot-*.log; do
        [ -f "$bot_log" ] || continue
        local bot
        bot=$(basename "$bot_log" .log | sed -E "s/^${name}_//")
        local strip_re=$'s/\x1b\\[[0-9;]*m//g; s/^\\[\\{[^}]*\\}\\] \\[Bot-[0-9]+\\] //'
        local jsx_line jsx_no jsx_text
        jsx_line=$(grep -nm1 -E 'JS Exception:|Assertion Failed' "$bot_log" || true)
        if [ -n "$jsx_line" ]; then
            jsx_no=${jsx_line%%:*}
            jsx_text=$(printf '%s\n' "${jsx_line#*:}" | sed -E "$strip_re")
            if printf '%s' "$jsx_text" | grep -q '\[object Object\]'; then
                local upstream
                upstream=$(head -n "$jsx_no" "$bot_log" \
                    | grep -E 'CALL_ERROR|REPLY [45][0-9][0-9]' \
                    | tail -1 | sed -E "$strip_re")
                if [ -n "$upstream" ]; then
                    echo "    [$bot] $jsx_text  (upstream: $upstream)"
                else
                    echo "    [$bot] $jsx_text"
                fi
            else
                echo "    [$bot] $jsx_text"
            fi
            found=1
            continue
        fi
        local fallback
        fallback=$(grep -E 'CALL_ERROR|REPLY [45][0-9][0-9]' "$bot_log" \
            | tail -1 | sed -E "$strip_re")
        if [ -n "$fallback" ]; then
            echo "    [$bot] $fallback"
            found=1
        fi
    done
    if [ $found -eq 0 ]; then
        echo "    (no JS exception or 4xx/5xx in bot logs — check $LOG_DIR/${name}*.log)"
    fi
}

run_test() {
    local script=$1
    local name=$(basename "$script" .js)
    local log_file="$LOG_DIR/${name}.log"

    # Determine agent count from filename suffix _with_N (default: 1)
    local agents=1
    if [[ "$name" =~ _with_([0-9]+)$ ]]; then
        agents="${BASH_REMATCH[1]}"
    fi

    echo -n "Running $name (Agents: $agents)... "

    # Construct paths array for the farm
    local paths=""
    for i in $(seq 1 "$agents"); do
        paths="$paths $script"
    done

    # Run the farm — the CLI inherits UPSILON_BASE_URL (the Caddy front door)
    # from the environment/compose; no flag needed.
    local start_time=$SECONDS
    if timeout 180 "$CLI" --farm -L "$LOG_DIR" $paths > /dev/null 2>&1; then
        local duration=$((SECONDS - start_time))
        if [ $duration -gt 10 ]; then
            echo -e "\033[32m[PASSED]\033[0m in ${duration}s \033[33m(WARNING: Slow test > 10s)\033[0m"
        else
            echo -e "\033[32m[PASSED]\033[0m in ${duration}s"
        fi
        echo "[SCENARIO_RESULT: PASSED]" >> "$log_file"
        echo "[SCENARIO_DURATION: ${duration}s]" >> "$log_file"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        local duration=$((SECONDS - start_time))
        echo -e "\033[31m[FAILED]\033[0m in ${duration}s"
        echo "[SCENARIO_RESULT: FAILED]" >> "$log_file"
        echo "[SCENARIO_DURATION: ${duration}s]" >> "$log_file"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_TESTS="$FAILED_TESTS $name"
        print_failure_reasons "$name"
        # Don't exit on failure, continue to other tests
    fi
}

# 4. Run Suite
# Start with E2E
echo "--- Running E2E Scenarios ---"
for script in $(ls $SCENARIO_DIR/e2e_*.js | sort); do
    run_test "$script"
done

# Then Edge Cases
echo ""
echo "--- Running Edge Case Tests ---"
for script in $(ls $SCENARIO_DIR/edge_*.js | sort); do
    run_test "$script"
done

# 5. Summary
echo ""
echo "=================================================="
echo "Local Suite Results:"
echo "  Passed: $PASSED_COUNT"
echo "  Failed: $FAILED_COUNT"
echo "  Total Duration: $((SECONDS - TOTAL_START_TIME))s"
echo "=================================================="

# 6. Report Generation
echo "Generating reports..."
if [ -f "./tests/ci_report.sh" ]; then
    ./tests/ci_report.sh > ci_report.md 2>/dev/null
    echo "  -> ci_report.md"
fi

if [ -f "./tests/edge_case_report.sh" ]; then
    ./tests/edge_case_report.sh > edge_case_report.md 2>/dev/null
    echo "  -> edge_case_report.md"
fi

if [ $FAILED_COUNT -gt 0 ]; then
    echo "FAILED: $FAILED_TESTS"
    exit 1
fi

exit 0
