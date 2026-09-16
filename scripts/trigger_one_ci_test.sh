#!/bin/bash
cd "$(dirname "$0")/.."
# trigger_one_test.sh - Run a single E2E or Edge Case test locally
# Usage: ./trigger_one_test.sh <script_name_or_path>

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

# 3. Parameter handling
SCRIPT=$1
if [ -z "$SCRIPT" ]; then
    echo "Usage: ./trigger_one_test.sh <script_name_or_path>"
    echo "Example: ./trigger_one_test.sh e2e_combat_turn_management"
    exit 1
fi

# Find the script if only name was provided.
# Normalize: accept the name with or without a trailing ".js", and with or
# without the "edge_" prefix (e.g. "char_reroll_post_match" resolves the same
# as "edge_char_reroll_post_match" or "edge_char_reroll_post_match.js").
if [ ! -f "$SCRIPT" ]; then
    BASE="${SCRIPT%.js}"
    FOUND=$(find upsiloncli/tests/scenarios -name "${BASE}.js" | head -n 1)
    if [ -z "$FOUND" ] && [[ "$BASE" != edge_* ]]; then
        FOUND=$(find upsiloncli/tests/scenarios -name "edge_${BASE}.js" | head -n 1)
    fi
    if [ -n "$FOUND" ]; then
        SCRIPT=$FOUND
    else
        echo "ERROR: Script not found: $SCRIPT"
        exit 1
    fi
fi

NAME=$(basename "$SCRIPT" .js)
LOG_DIR="upsiloncli/tests/logs"
LOG_FILE="$LOG_DIR/${NAME}.log"
mkdir -p "$LOG_DIR"

# 4. Determine agent count from _with_N filename suffix (canonical convention).
AGENTS=1
if [[ "$NAME" == *"_with_4"* ]] || [[ "$NAME" == *"2v2"* ]]; then
    AGENTS=4
elif [[ "$NAME" == *"_with_2"* ]]; then
    AGENTS=2
fi

echo "=================================================="
echo "Running $NAME (Agents: $AGENTS)... "
echo "Log: $LOG_FILE"
echo "=================================================="

# Construct paths array for the farm
PATHS=""
for i in $(seq 1 "$AGENTS"); do
    PATHS="$PATHS $SCRIPT"
done

# Print a one-line failure reason per bot log for this scenario.
# See trigger_all_ci_tests.sh for the extraction strategy.
print_failure_reasons() {
    local found=0
    for bot_log in "$LOG_DIR/${NAME}"_Bot-*.log; do
        [ -f "$bot_log" ] || continue
        local bot
        bot=$(basename "$bot_log" .log | sed -E "s/^${NAME}_//")
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
                    echo "  [$bot] $jsx_text  (upstream: $upstream)"
                else
                    echo "  [$bot] $jsx_text"
                fi
            else
                echo "  [$bot] $jsx_text"
            fi
            found=1
            continue
        fi
        local fallback
        fallback=$(grep -E 'CALL_ERROR|REPLY [45][0-9][0-9]' "$bot_log" \
            | tail -1 | sed -E "$strip_re")
        if [ -n "$fallback" ]; then
            echo "  [$bot] $fallback"
            found=1
        fi
    done
    if [ $found -eq 0 ]; then
        echo "  (no JS exception or 4xx/5xx found in bot logs)"
    fi
}

# Run the farm — the CLI inherits UPSILON_BASE_URL (the Caddy front door)
# from the environment/compose; no flag needed.
# No timeout here to allow debugging, but follow same structure as CI
START_TIME=$SECONDS
if "$CLI" --farm -L "$LOG_DIR" $PATHS ; then
    DURATION=$((SECONDS - START_TIME))
    if [ $DURATION -gt 10 ]; then
        echo -e "\033[32m[PASSED]\033[0m in ${DURATION}s \033[33m(WARNING: Slow test > 10s)\033[0m"
    else
        echo -e "\033[32m[PASSED]\033[0m in ${DURATION}s"
    fi
    echo "[SCENARIO_RESULT: PASSED]" >> "$LOG_FILE"
    echo "[SCENARIO_DURATION: ${DURATION}s]" >> "$LOG_FILE"
    exit 0
else
    DURATION=$((SECONDS - START_TIME))
    echo -e "\033[31m[FAILED]\033[0m in ${DURATION}s"
    echo "[SCENARIO_RESULT: FAILED]" >> "$LOG_FILE"
    echo "[SCENARIO_DURATION: ${DURATION}s]" >> "$LOG_FILE"
    echo "Failure reasons:"
    print_failure_reasons
    echo "Check logs at: $LOG_FILE (and ${LOG_DIR}/${NAME}_Bot-*.log)"
    exit 1
fi
