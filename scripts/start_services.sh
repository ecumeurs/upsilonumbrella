#!/bin/bash
cd "$(dirname "$0")/.."

# Configuration
LOG_DIR="logs"
PID_FILE=".services.pids"
PORTS_VERIFY_TIMEOUT=10 # Max seconds to wait for a port

# Phase-3 economy swap: run the extracted upsiloneconomy alongside the hub so
# local dev mirrors prod (the hub talks to it over the internal S2S seam).
# DEV_S2S_TOKEN is the shared internal-service secret both sides present/expect;
# ECONOMY_DB_URL is the hub's DATABASE_URL retargeted at the upsiloneconomy
# database (provisioned by deploy/initdb on a fresh dev volume).
# DEV_S2S_TOKEN and the *_INTERNAL_URL values below inherit from the
# environment (set at compose level in docker-compose.yaml for the dev
# topology) with the current dev values as fallback defaults, so this script
# still works standalone if someone runs it outside compose.
DEV_S2S_TOKEN="${S2S_TOKEN:-dev-internal-token}"
ECONOMY_DB_URL="$(printf '%s' "$DATABASE_URL" | sed -E 's#(://[^/]+/)[^/?]+#\1upsiloneconomy#')"

# Phase-4 auth cutover: run the extracted upsilonauth alongside the hub — it
# is now the sole owner of register/login/admin-account routes (Caddy routes
# to it directly) and the hub introspects bearers over the internal S2S seam.
# AUTH_DB_URL mirrors ECONOMY_DB_URL's retargeting (provisioned by deploy/initdb).
AUTH_DB_URL="$(printf '%s' "$DATABASE_URL" | sed -E 's#(://[^/]+/)[^/?]+#\1upsilonauth#')"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

echo "---------------------------------------"
echo "Starting Upsilon Stack (Authoritative Mode)"
echo "---------------------------------------"

# 1. Authoritative Cleanup
./scripts/stop_services.sh

# Clear existing PIDs file
> "$PID_FILE"

# Function to start a service and verify it is listening
start_service() {
    local name=$1
    local dir=$2
    local command=$3
    local log_file=$4
    local port=$5

    echo "[+] Starting $name on port $port..."
    cd "$dir" || exit 1
    
    # Run in background
    nohup $command > "../$LOG_DIR/$log_file" 2>&1 &
    local shell_pid=$!
    
    # Verification loop
    echo -n "    Verifying..."
    local count=0
    local confirmed_pid=""
    while [ $count -lt $PORTS_VERIFY_TIMEOUT ]; do
        # Try to find the PID actually listening on the port
        confirmed_pid=$(ss -tulpn | grep ":$port " | grep -oP 'users:\(\("\S+",pid=\K\d+' | head -n 1)
        
        if [ ! -z "$confirmed_pid" ]; then
            echo " OK (PID: $confirmed_pid)"
            # Format: NAME|PID|LOG_FILE|PORT
            echo "$name|$confirmed_pid|$log_file|$port" >> "../$PID_FILE"
            cd ..
            return 0
        fi
        
        sleep 1
        echo -n "."
        count=$((count + 1))
    done

    echo " FAILED"
    echo "[ERROR] $name failed to start on port $port after $PORTS_VERIFY_TIMEOUT seconds."
    echo "Check logs/ $log_file for details."
    cd ..
    exit 1
}


# 1. Upsilon Engine (Go) — before the hub so its client finds it at boot
start_service "Upsilon Engine" "upsilonapi" "./bin/upsilonapi" "engine.log" 8081

# 2. Upsilon Economy (Go) — before the hub so the S2S seam is live at boot.
# Its database is a separate schema; provision it (migrate + seed the catalog)
# on every start — both are idempotent, so a warm dev volume is a no-op.
echo "[+] Provisioning economy database (migrate + seed)..."
( cd upsiloneconomy \
    && env DATABASE_URL="$ECONOMY_DB_URL" ./bin/upsiloneconomy -migrate \
    && env DATABASE_URL="$ECONOMY_DB_URL" ./bin/upsiloneconomy -seed ) \
    || { echo "[ERROR] economy migrate/seed failed (is the upsiloneconomy DB provisioned? 'docker compose down -v' to reprovision)"; exit 1; }
start_service "Upsilon Economy" "upsiloneconomy" "env DATABASE_URL=$ECONOMY_DB_URL S2S_TOKEN=$DEV_S2S_TOKEN APP_DEBUG=true ./bin/upsiloneconomy" "economy.log" 8092

# 3. Upsilon Auth (Go) — before the hub so introspection is live at boot and
# register/login work from the moment Caddy is up. Its database is a separate
# schema; provision it (migrate + seed the well-known accounts) on every start.
# HUB_INTERNAL_URL lets its AccountPush producer reach the hub's internal seam;
# ECONOMY_INTERNAL_URL lets its GDPR export collector fan out to the economy
# service (without it, export fail-closes and composition serves placeholders),
# and selects the economy_purge worker so the erasure fan-out actually drains
# (ISS-165); unset, purges park on their own durable queue (never consumed by
# the account_push worker) and drain on a later boot that configures economy.
echo "[+] Provisioning auth database (migrate + seed)..."
( cd upsilonauth \
    && env DATABASE_URL="$AUTH_DB_URL" ./bin/upsilonauth -migrate \
    && env DATABASE_URL="$AUTH_DB_URL" ./bin/upsilonauth -seed ) \
    || { echo "[ERROR] auth migrate/seed failed (is the upsilonauth DB provisioned? 'docker compose down -v' to reprovision)"; exit 1; }
start_service "Upsilon Auth" "upsilonauth" "env DATABASE_URL=$AUTH_DB_URL S2S_TOKEN=$DEV_S2S_TOKEN APP_DEBUG=true HUB_INTERNAL_URL=${HUB_INTERNAL_URL:-http://localhost:8090} ECONOMY_INTERNAL_URL=${ECONOMY_INTERNAL_URL:-http://localhost:8092} ./bin/upsilonauth" "auth.log" 8091

# 4. Upsilon Hub (API + SSE + SPA). DATABASE_URL comes from the devcontainer
# env; APP_DEBUG=true is required for the '-- DEBUG MODE -- ' exception-prefix
# parity the CLI edge suites assert. ECONOMY_INTERNAL_URL + S2S_TOKEN swap the
# in-process economy for the extracted service (Phase 3); AUTH_INTERNAL_URL is
# a hard cutover (Phase 4, no rollback flag) — the hub always introspects auth.
start_service "Upsilon Hub" "upsilonhub" "env APP_DEBUG=true UPSILON_API_URL=${UPSILON_API_URL:-http://localhost:8081} HUB_SPA_DIR=/workspace/upsilonbattleui/dist ECONOMY_INTERNAL_URL=${ECONOMY_INTERNAL_URL:-http://localhost:8092} AUTH_INTERNAL_URL=${AUTH_INTERNAL_URL:-http://localhost:8091} S2S_TOKEN=$DEV_S2S_TOKEN ./bin/upsilonhub" "hub.log" 8090

# 5. Vue Frontend (Vite dev server, proxies /api + /up to the :8085 front door)
start_service "Vue Frontend" "upsilonbattleui" "npm run dev" "vite.log" 5173

echo "---------------------------------------"
echo "All services are running and verified."
echo "Logs: $LOG_DIR/"
echo "Stop: ./scripts/stop_services.sh"
echo "---------------------------------------"

