#!/bin/bash
cd "$(dirname "$0")/.."

# Configuration
PID_FILE=".services.pids"
STATUS_CODE=0

if [ ! -f "$PID_FILE" ]; then
    echo "ERROR: No services are currently tracked (missing $PID_FILE)."
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Process / port liveness — is each tracked PID alive and bound to its port?
# ---------------------------------------------------------------------------
echo "--- Upsilon Service Status ---"

while IFS='|' read -r name pid log port; do
    if [ ! -z "$pid" ]; then
        if ps -p "$pid" > /dev/null; then
            if [ ! -z "$port" ] && ss -Hlntp "sport = :$port" | grep -q "pid=$pid,"; then
                echo "[RUNNING] $name (PID: $pid, Port: $port)"
            elif [ ! -z "$port" ]; then
                echo "[PENDING] $name (PID: $pid, Waiting for Port $port...)"
            else
                echo "[RUNNING] $name (PID: $pid)"
            fi
        else
            echo "[ DOWN  ] $name (PID: $pid)"
            STATUS_CODE=1
        fi
    fi
done < "$PID_FILE"

# ---------------------------------------------------------------------------
# 2. HTTP-level health — a port can be bound but the process wedged/deadlocked
#    behind it; hit each service's own liveness route to confirm it actually
#    answers requests. (upsilonapi uses /health; the others use /up.)
# ---------------------------------------------------------------------------
echo ""
echo "--- HTTP Health ---"

http_check() {
    local name=$1
    local url=$2
    local code
    code=$(curl -sf -m 3 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    if [ "$code" = "200" ]; then
        echo "[  OK   ] $name ($url)"
    else
        echo "[ FAIL  ] $name ($url) — unreachable or non-200 (got '${code:-none}')"
        STATUS_CODE=1
    fi
}

http_check "Upsilon Engine" "http://127.0.0.1:8081/health"
http_check "Upsilon Economy" "http://127.0.0.1:8092/up"
http_check "Upsilon Auth" "http://127.0.0.1:8091/up"
http_check "Upsilon Hub" "http://127.0.0.1:8090/up"
http_check "Vue Frontend" "http://127.0.0.1:5173/"

# Front door: confirm Caddy is actually routing, not just that the upstreams
# answer directly (catches Caddyfile/env misrouting that per-port checks miss).
if command -v curl > /dev/null 2>&1; then
    http_check "Front Door -> Hub (proxy:8085)" "http://proxy:8085/up"
    http_check "Front Door -> Auth (proxy:8085)" "http://proxy:8085/api/v1/auth/up"
fi

# ---------------------------------------------------------------------------
# 3. Database schema depth — a service can be up and answering /up while its
#    database has never been migrated (the hub's migrate/seed is NOT wired
#    into start_services.sh — see the dev-env skill's Gotcha #3). Confirm
#    each service's database exists, has been migrated to the version its
#    own migrations/ directory expects, and isn't left dirty by a failed run.
# ---------------------------------------------------------------------------
echo ""
echo "--- Database Schema ---"

BASE_DB_URL="${DATABASE_URL:-postgres://postgres:postgres@db:5432/upsilon?sslmode=disable}"
BASE_DB_URL="${BASE_DB_URL%%\?*}"
DB_HOST=$(printf '%s' "$BASE_DB_URL" | sed -E 's#^[a-z]+://[^@]*@([^:/]+).*#\1#')
DB_PORT=$(printf '%s' "$BASE_DB_URL" | sed -E 's#^[a-z]+://[^@]*@[^:/]+:?([0-9]*)/.*#\1#')
DB_PORT="${DB_PORT:-5432}"

if ! command -v psql > /dev/null 2>&1; then
    echo "[ SKIP  ] psql not installed — cannot inspect database schema."
elif ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -t 3 > /dev/null 2>&1; then
    echo "[ FAIL  ] Postgres unreachable at $DB_HOST:$DB_PORT — skipping per-service schema checks."
    STATUS_CODE=1
else
    db_url_for() {
        printf '%s' "$BASE_DB_URL" | sed -E "s#(://[^/]+/)[^/]+\$#\1$1?sslmode=disable#"
    }

    expected_version_for() {
        local migrations_dir=$1
        ls "$migrations_dir"/*.up.sql 2>/dev/null \
            | sed -E 's#.*/0*([0-9]+)_.*#\1#' \
            | sort -n | tail -1
    }

    check_schema() {
        local label=$1 url=$2 migrations_dir=$3 expected_db=$4
        local db_name expected row version dirty
        db_name=$(printf '%s' "$url" | sed -E 's#.*/([^/?]+)(\?.*)?$#\1#')

        # Crash-early guard (ISS-161): each service's DATABASE_URL path segment
        # must match its expected per-service database. This used to be a
        # purely descriptive read (the hub silently ran against "postgres"
        # instead of "upsilon" for a long stretch); now it fails loudly instead
        # of quietly reporting schema health for the wrong database.
        if [ "$db_name" != "$expected_db" ]; then
            echo "[ FAIL  ] $label: DATABASE_URL points at \"$db_name\", expected \"$expected_db\" — database mismatch"
            STATUS_CODE=1
            return
        fi

        expected="$(expected_version_for "$migrations_dir")"
        [ -z "$expected" ] && expected=0

        row=$(PGCONNECT_TIMEOUT=3 psql "$url" -tAc \
            "SELECT version, dirty FROM schema_migrations;" 2>&1)

        if printf '%s' "$row" | grep -q "database .* does not exist"; then
            echo "[ FAIL  ] $label: database \"$db_name\" does not exist (run deploy/initdb/create_databases.sql)"
            STATUS_CODE=1
        elif printf '%s' "$row" | grep -q "does not exist"; then
            echo "[ FAIL  ] $label: no schema_migrations table in \"$db_name\" — never migrated (expects v$expected)"
            STATUS_CODE=1
        elif printf '%s' "$row" | grep -qE "^[0-9]+\|"; then
            version="${row%%|*}"
            dirty="${row##*|}"
            if [ "$dirty" = "t" ]; then
                echo "[ FAIL  ] $label: schema_migrations is DIRTY at v$version — a prior migrate run failed partway"
                STATUS_CODE=1
            elif [ "$version" -lt "$expected" ]; then
                echo "[ FAIL  ] $label: schema at v$version, code expects v$expected — needs -migrate"
                STATUS_CODE=1
            elif [ "$version" -gt "$expected" ]; then
                echo "[ WARN  ] $label: schema at v$version is AHEAD of code's v$expected (checked-out revision behind DB?)"
            else
                echo "[  OK   ] $label: \"$db_name\" at v$version, not dirty"
            fi
        else
            echo "[ FAIL  ] $label: could not read schema_migrations in \"$db_name\" — $row"
            STATUS_CODE=1
        fi
    }

    # Per-service database topology (ISS-161, resolved): the hub's own
    # DATABASE_URL (declared in docker-compose.yaml) now targets the
    # dedicated "upsilon" database deploy/initdb provisions for it, matching
    # the sed-based retargeting start_services.sh already does for
    # economy/auth. check_schema asserts each URL's path segment against its
    # expected name below rather than just reporting whatever it finds.
    check_schema "Upsilon Hub" "${BASE_DB_URL}?sslmode=disable" "upsilonhub/db/migrations" "upsilon"
    check_schema "Upsilon Auth" "$(db_url_for upsilonauth)" "upsilonauth/db/migrations" "upsilonauth"
    check_schema "Upsilon Economy" "$(db_url_for upsiloneconomy)" "upsiloneconomy/db/migrations" "upsiloneconomy"
fi

# ---------------------------------------------------------------------------
echo ""
if [ $STATUS_CODE -eq 0 ]; then
    echo "------------------------------"
    echo "All services are operational."
else
    echo "------------------------------"
    echo "WARNING: One or more checks failed."
fi

exit $STATUS_CODE
