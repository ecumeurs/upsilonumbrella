#!/bin/bash
cd "$(dirname "$0")/.."
# trigger_quick_ci_tests.sh - Run critical E2E and Playwright tests locally

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
echo "      UPSILON QUICK CI TEST TRIGGER"
echo "=================================================="

# 0. Reset and seed database
echo "Resetting and seeding database..."
./scripts/seed_ci.sh

FAILED_TESTS=""
PASSED_COUNT=0
FAILED_COUNT=0
TOTAL_START_TIME=$SECONDS

# Helper to print failure reasons from bot logs
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

run_e2e_test() {
    local script_name=$1
    local script="$SCENARIO_DIR/$script_name"
    if [ ! -f "$script" ]; then
        echo -e "\033[31m[MISSING]\033[0m $script_name"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_TESTS="$FAILED_TESTS $script_name"
        return
    fi

    local name=$(basename "$script" .js)
    local log_file="$LOG_DIR/${name}.log"

    # Determine agent count from filename suffix _with_N (default: 1)
    local agents=1
    if [[ "$name" =~ _with_([0-9]+)$ ]]; then
        agents="${BASH_REMATCH[1]}"
    fi

    echo -n "Running E2E: $name (Agents: $agents)... "

    # Construct paths array for the farm
    local paths=""
    for i in $(seq 1 "$agents"); do
        paths="$paths $script"
    done

    # Run the farm — the CLI inherits UPSILON_BASE_URL (the Caddy front door)
    # from the environment/compose; no flag needed.
    local start_time=$SECONDS
    if timeout 120 "$CLI" --farm -L "$LOG_DIR" $paths > /dev/null 2>&1; then
        local duration=$((SECONDS - start_time))
        echo -e "\033[32m[PASSED]\033[0m in ${duration}s"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        local duration=$((SECONDS - start_time))
        echo -e "\033[31m[FAILED]\033[0m in ${duration}s"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_TESTS="$FAILED_TESTS $name"
        print_failure_reasons "$name"
    fi
}

# 4. Run Critical E2E Scenarios
echo "--- Running Critical E2E Scenarios ---"
run_e2e_test "e2e_combat_turn_management.js"
run_e2e_test "e2e_skill_roll_inventory.js"
run_e2e_test "e2e_shop_browse_purchase.js"
run_e2e_test "e2e_item_grants_skill.js"

# 5. Run Playwright Tests
echo ""
echo "--- Running Critical Playwright Tests ---"
cd upsilonbattleui
if [ ! -d "node_modules" ]; then
    echo "Installing upsilonbattleui dependencies..."
    npm install > /dev/null 2>&1
fi

run_playwright() {
    local spec=$1
    echo -n "Running Playwright: $spec... "
    local start_time=$SECONDS
    if npx playwright test --workers=1 "tests/playwright/$spec" > playwright_last_run.log 2>&1; then
        local duration=$((SECONDS - start_time))
        echo -e "\033[32m[PASSED]\033[0m in ${duration}s"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        local duration=$((SECONDS - start_time))
        echo -e "\033[31m[FAILED]\033[0m in ${duration}s"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_TESTS="$FAILED_TESTS $spec"
        echo "    (Check upsilonbattleui/playwright_last_run.log for details)"
    fi
}

run_playwright "battle_arena_sandbox.spec.ts"
run_playwright "battle_arena.spec.ts"
cd ..

# 6. Summary
echo ""
echo "=================================================="
echo "Quick CI Suite Results:"
echo "  Passed: $PASSED_COUNT"
echo "  Failed: $FAILED_COUNT"
echo "  Total Duration: $((SECONDS - TOTAL_START_TIME))s"
echo "=================================================="

if [ $FAILED_COUNT -gt 0 ]; then
    echo "FAILED: $FAILED_TESTS"
    exit 1
fi

exit 0
