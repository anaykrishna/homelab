# Immich Homelab Photo-Backup Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce all config files, scripts, and setup checklists to run a self-hosted Immich photo-backup server on an old all-in-one Debian 13 PC that auto-wakes at 9 PM for backups and auto-shuts-down when idle.

**Architecture:** Immich runs as a 4-container Docker Compose stack. A thin host layer of bash scripts + systemd units (1) arms the hardware RTC alarm to power the PC on at 21:00 and (2) shuts it down only when nobody is at the desktop and no uploads are running. A manual export script mirrors the archive to a USB drive. Tailscale provides free remote viewing.

**Tech Stack:** Docker Compose, Immich (`:release` images), Postgres (pgvector), Valkey/Redis, systemd, bash, `rtcwake`/`/sys/class/rtc/rtc0/wakealarm`, Tailscale.

## Global Constraints

- **Authoring vs. server split:** All files are authored on this Debian 12 machine under `~/homelab-immich/`. Every server-bound file begins with a header comment stating its exact intended path on the Debian 13 server. Server-only actions (BIOS, systemctl, docker) are delivered as checklists for the user to run — never executed from here.
- **Server target paths:** Immich stack → `/opt/immich/`; scripts → `/usr/local/bin/`; shared lib → `/usr/local/lib/immich/`; systemd units → `/etc/systemd/system/`.
- **Photo storage:** `UPLOAD_LOCATION=/photos` on the server's single internal drive. Originals stored as plain files.
- **Wake time:** 21:00 (9:00 PM) local. **Min uptime before auto-shutdown is permitted:** 2700 s (45 min).
- **Secrets:** `config/.env` (real credentials) is gitignored; only `config/.env.example` is committed.
- **No internet exposure:** no router port-forwarding; remote access via Tailscale only. No HTTPS in v1.
- **Old hardware:** Intel i3 M 380 (2c/4t, no AVX), 8 GB RAM. ML container memory-limited; job concurrency tuned to 1 post-install.
- **Test harness:** zero-dependency bash (`tests/run.sh`); no bats/shellcheck assumed. Config validated with `docker compose config` and `python3`.

---

### Task 1: Project scaffolding + bash test harness

**Files:**
- Create: `tests/assert.sh`
- Create: `tests/run.sh`
- Create: `tests/sample_test.sh`
- Create: `README.md`

**Interfaces:**
- Produces: `tests/assert.sh` exposing `assert_eq <actual> <expected> <label>` (prints `PASS`/`FAIL`, increments counters, sets non-zero exit on any failure); `tests/run.sh` which sources and runs every `tests/*_test.sh` file and exits non-zero if any assertion failed.

- [ ] **Step 1: Write the assertion helper**

Create `tests/assert.sh`:

```bash
#!/usr/bin/env bash
# Tiny zero-dependency assertion helper for plan tests.
# Sourced by tests/run.sh and by individual *_test.sh files.

ASSERT_PASS=0
ASSERT_FAIL=0

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $label"
    ASSERT_PASS=$((ASSERT_PASS + 1))
  else
    echo "FAIL: $label"
    echo "  expected: [$expected]"
    echo "  actual:   [$actual]"
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
  fi
}
```

- [ ] **Step 2: Write the test runner**

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
# Runs every tests/*_test.sh and reports a combined pass/fail total.
set -u
cd "$(dirname "$0")"
source ./assert.sh

for t in *_test.sh; do
  [[ -e "$t" ]] || continue
  echo "== $t =="
  # shellcheck disable=SC1090
  source "./$t"
done

echo "-----------------------------"
echo "PASS=$ASSERT_PASS FAIL=$ASSERT_FAIL"
[[ "$ASSERT_FAIL" -eq 0 ]]
```

- [ ] **Step 3: Write a sample test to prove the harness fails on a bad assertion**

Create `tests/sample_test.sh`:

```bash
# Sanity test for the harness itself.
assert_eq "hello" "hello" "harness reports equal strings as PASS"
```

- [ ] **Step 4: Run the harness, verify it passes**

Run: `bash tests/run.sh`
Expected: ends with `PASS=1 FAIL=0` and exit code 0.

- [ ] **Step 5: Verify the harness catches failures**

Run: `bash -c 'source tests/assert.sh; assert_eq a b x; echo "exit_fail=$ASSERT_FAIL"'`
Expected: prints `FAIL: x` and `exit_fail=1`.

- [ ] **Step 6: Write the README**

Create `README.md`:

```markdown
# Homelab Immich Photo-Backup Server

Config + scripts for a self-hosted Immich server on an old all-in-one Debian 13 PC
that auto-wakes at 21:00 for backups and auto-shuts-down when idle.

- Design spec: `docs/superpowers/specs/2026-06-30-immich-homelab-photo-backup-design.md`
- Implementation plan: `docs/superpowers/plans/2026-06-30-immich-homelab-photo-backup.md`
- Server-bound files live in `config/` (each has a header with its server path).
- Setup checklists (run on the server): `docs/setup/`.
- Run logic tests: `bash tests/run.sh`

Files are authored here, then copied to the Debian 13 server. See `docs/setup/`.
```

- [ ] **Step 7: Commit**

```bash
git add tests README.md
git commit -m "chore: add bash test harness and project readme"
```

---

### Task 2: Immich Docker Compose stack + env template

**Files:**
- Create: `config/docker-compose.yml`  (server: `/opt/immich/docker-compose.yml`)
- Create: `config/.env.example`  (server: `/opt/immich/.env`, filled with real secrets)

**Interfaces:**
- Produces: a stack named `immich` with containers `immich_server` (port 2283), `immich_machine_learning` (mem-limited), `immich_redis`, `immich_postgres`. Env keys consumed by later tasks: `UPLOAD_LOCATION=/photos`, `DB_USERNAME`, `DB_DATABASE_NAME`, `DB_DATA_LOCATION`. Postgres container name `immich_postgres` is consumed by the export script (Task 6).

- [ ] **Step 1: Write the compose file**

Create `config/docker-compose.yml`:

```yaml
# Server path: /opt/immich/docker-compose.yml
# Immich photo-backup stack. Image tags track ":release"; pin IMMICH_VERSION in .env
# when you want to freeze a version. Customizations vs. upstream: restart: always on
# every service, and a memory limit on the ML container for the 8 GB host.
name: immich

services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}
    volumes:
      - ${UPLOAD_LOCATION}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    ports:
      - '2283:2283'
    depends_on:
      - redis
      - database
    restart: always

  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}
    volumes:
      - model-cache:/cache
    env_file:
      - .env
    restart: always
    mem_limit: 3g

  redis:
    container_name: immich_redis
    image: docker.io/valkey/valkey:8-bookworm
    healthcheck:
      test: redis-cli ping || exit 1
    restart: always

  database:
    container_name: immich_postgres
    image: ghcr.io/immich-app/postgres:14-vectorchord0.3.0
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE_NAME}
    volumes:
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data
    restart: always

volumes:
  model-cache:
```

- [ ] **Step 2: Write the env template**

Create `config/.env.example`:

```bash
# Server path: /opt/immich/.env  (copy from this template, fill real values, never commit)
# The location where your uploaded photos/videos are stored (single internal drive).
UPLOAD_LOCATION=/photos
# The Postgres data directory on the host.
DB_DATA_LOCATION=/opt/immich/postgres
# Pin a specific version here (e.g. v1.119.0) or leave as release.
IMMICH_VERSION=release
# Database connection — set DB_PASSWORD to a long random string.
DB_PASSWORD=CHANGE_ME_long_random_string
DB_USERNAME=immich
DB_DATABASE_NAME=immich
# Local timezone (used by containers).
TZ=Asia/Kolkata
```

- [ ] **Step 3: Validate compose syntax + variable interpolation**

Run:
```bash
cp config/.env.example config/.env.validate && \
docker compose --env-file config/.env.validate -f config/docker-compose.yml config >/dev/null && \
echo VALID && rm -f config/.env.validate
```
Expected: prints `VALID` (compose parses and all `${VAR}` resolve).

- [ ] **Step 4: Assert the four required services and key settings exist**

Create `tests/compose_test.sh`:

```bash
# Validates the rendered compose has the four services and required customizations.
cp config/.env.example config/.env.validate
RENDER=$(docker compose --env-file config/.env.validate -f config/docker-compose.yml config 2>/dev/null)
rm -f config/.env.validate

has() { grep -q "$1" <<<"$RENDER" && echo yes || echo no; }

assert_eq "$(has 'container_name: immich_server')"            "yes" "compose has immich_server"
assert_eq "$(has 'container_name: immich_machine_learning')"  "yes" "compose has ML container"
assert_eq "$(has 'container_name: immich_redis')"             "yes" "compose has redis"
assert_eq "$(has 'container_name: immich_postgres')"          "yes" "compose has postgres"
assert_eq "$(grep -c 'restart: always' <<<"$RENDER")"         "4"   "all four services restart: always"
assert_eq "$(has '/photos')"                                  "yes" "UPLOAD_LOCATION resolves to /photos"
```

- [ ] **Step 5: Run tests, verify pass**

Run: `bash tests/run.sh`
Expected: ends with `FAIL=0`.

- [ ] **Step 6: Commit**

```bash
git add config/docker-compose.yml config/.env.example tests/compose_test.sh
git commit -m "feat: add immich docker compose stack and env template"
```

---

### Task 3: Auto-shutdown decision logic (pure, TDD)

**Files:**
- Create: `config/bin/lib/shutdown-decision.sh`  (server: `/usr/local/lib/immich/shutdown-decision.sh`)
- Create: `tests/shutdown_decision_test.sh`

**Interfaces:**
- Produces: `should_shutdown <uptime_secs> <min_uptime_secs> <user_active:0|1> <uploads_active:0|1>` — prints `shutdown <reason>` or `stay <reason>`; pure (no system calls). Consumed by the guard wiring in Task 4.

- [ ] **Step 1: Write the failing tests**

Create `tests/shutdown_decision_test.sh`:

```bash
source ./config/bin/lib/shutdown-decision.sh

# field of the decision string we care about
verb() { awk '{print $1}'; }

assert_eq "$(should_shutdown 600  2700 0 0 | verb)" "stay"     "below min uptime -> stay"
assert_eq "$(should_shutdown 3000 2700 1 0 | verb)" "stay"     "user active -> stay"
assert_eq "$(should_shutdown 3000 2700 0 1 | verb)" "stay"     "uploads active -> stay"
assert_eq "$(should_shutdown 3000 2700 0 0 | verb)" "shutdown" "idle + past window -> shutdown"
assert_eq "$(should_shutdown 2700 2700 0 0 | verb)" "shutdown" "exactly at min uptime -> shutdown"
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL lines for the shutdown_decision cases (function not defined yet).

- [ ] **Step 3: Implement the decision function**

Create `config/bin/lib/shutdown-decision.sh`:

```bash
#!/usr/bin/env bash
# Server path: /usr/local/lib/immich/shutdown-decision.sh
# Pure decision logic for the auto-shutdown guard. No side effects — unit-testable.

# should_shutdown <uptime_secs> <min_uptime_secs> <user_active:0|1> <uploads_active:0|1>
# Prints "shutdown <reason>" or "stay <reason>".
should_shutdown() {
  local uptime_secs="$1" min_uptime="$2" user_active="$3" uploads_active="$4"

  if (( uptime_secs < min_uptime )); then
    echo "stay uptime_below_min(${uptime_secs}s<${min_uptime}s)"
    return 0
  fi
  if (( user_active == 1 )); then
    echo "stay user_active"
    return 0
  fi
  if (( uploads_active == 1 )); then
    echo "stay uploads_active"
    return 0
  fi
  echo "shutdown idle_and_past_window"
  return 0
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run.sh`
Expected: all shutdown_decision assertions PASS, `FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add config/bin/lib/shutdown-decision.sh tests/shutdown_decision_test.sh
git commit -m "feat: add pure auto-shutdown decision logic with tests"
```

---

### Task 4: Auto-shutdown guard wiring + systemd timer

**Files:**
- Create: `config/bin/immich-autoshutdown.sh`  (server: `/usr/local/bin/immich-autoshutdown.sh`)
- Create: `config/systemd/immich-autoshutdown.service`  (server: `/etc/systemd/system/immich-autoshutdown.service`)
- Create: `config/systemd/immich-autoshutdown.timer`  (server: `/etc/systemd/system/immich-autoshutdown.timer`)

**Interfaces:**
- Consumes: `should_shutdown` from `/usr/local/lib/immich/shutdown-decision.sh`.
- Produces: an executable guard that gathers real signals (uptime, desktop idle, Immich job activity) and, when the decision is `shutdown`, arms the next wake (calls `immich-set-wake.sh` from Task 5) and powers off. Honors `DRY_RUN=1` (logs the action instead of executing it).

- [ ] **Step 1: Write the guard script**

Create `config/bin/immich-autoshutdown.sh`:

```bash
#!/usr/bin/env bash
# Server path: /usr/local/bin/immich-autoshutdown.sh
# Runs every ~10 min via systemd timer. Shuts the PC down only when it is past the
# backup window, nobody is at the desktop, and no Immich uploads/jobs are active.
# Set DRY_RUN=1 to log the decision without arming wake or powering off.
set -euo pipefail

MIN_UPTIME="${MIN_UPTIME:-2700}"          # 45 min
IDLE_THRESHOLD_MS="${IDLE_THRESHOLD_MS:-900000}"  # 15 min of no input = "not active"
LIB="${LIB:-/usr/local/lib/immich/shutdown-decision.sh}"
SET_WAKE="${SET_WAKE:-/usr/local/bin/immich-set-wake.sh}"

# shellcheck source=/dev/null
source "$LIB"

log() { echo "[immich-autoshutdown] $*"; }

# --- uptime in seconds ---
uptime_secs=$(awk '{print int($1)}' /proc/uptime)

# --- desktop activity: 1 if any seat has a logged-in user whose idle time is short ---
# loginctl IdleSinceHint is unreliable across DEs, so use the smallest idle across
# active graphical sessions via the session's IdleHint, falling back to "active if any
# active graphical session exists".
user_active=0
if command -v loginctl >/dev/null 2>&1; then
  while read -r sid; do
    [[ -z "$sid" ]] && continue
    state=$(loginctl show-session "$sid" -p State --value 2>/dev/null || echo "")
    typ=$(loginctl show-session "$sid" -p Type --value 2>/dev/null || echo "")
    idlehint=$(loginctl show-session "$sid" -p IdleHint --value 2>/dev/null || echo "")
    if [[ "$typ" == "x11" || "$typ" == "wayland" ]] && [[ "$state" == "active" ]] && [[ "$idlehint" != "yes" ]]; then
      user_active=1
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}')
fi

# --- Immich job/upload activity: 1 if any non-idle job queue ---
# Asks the server's metrics-free way: count active+waiting jobs via the API requires a
# key, so instead detect in-flight uploads as established connections to port 2283.
uploads_active=0
if command -v ss >/dev/null 2>&1; then
  conns=$(ss -Htn state established '( dport = :2283 or sport = :2283 )' 2>/dev/null | wc -l)
  (( conns > 0 )) && uploads_active=1
fi

decision="$(should_shutdown "$uptime_secs" "$MIN_UPTIME" "$user_active" "$uploads_active")"
log "uptime=${uptime_secs}s user_active=${user_active} uploads_active=${uploads_active} -> ${decision}"

if [[ "${decision%% *}" == "shutdown" ]]; then
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "DRY_RUN: would arm next wake and power off now"
    exit 0
  fi
  "$SET_WAKE" || log "WARN: failed to arm next wake alarm"
  log "powering off"
  systemctl poweroff
fi
```

- [ ] **Step 2: Syntax-check the script**

Run: `bash -n config/bin/immich-autoshutdown.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`.

- [ ] **Step 3: Add a DRY_RUN behavior test using stubs**

Create `tests/autoshutdown_test.sh`:

```bash
# Exercises the guard end-to-end with stubbed system tools, asserting it reaches the
# "would power off" path only when idle+past-window, and never actually powers off.
_tmp=$(mktemp -d)

# stub lib that forces a deterministic decision input path
cat >"$_tmp/shutdown-decision.sh" <<'EOF'
should_shutdown() { echo "shutdown idle_and_past_window"; }
EOF

# stub set-wake so it records it was called
cat >"$_tmp/set-wake.sh" <<'EOF'
#!/usr/bin/env bash
echo "set-wake-called" >>"$WAKE_LOG"
EOF
chmod +x "$_tmp/set-wake.sh"

WAKE_LOG="$_tmp/wake.log"; : >"$WAKE_LOG"
out=$(DRY_RUN=1 LIB="$_tmp/shutdown-decision.sh" SET_WAKE="$_tmp/set-wake.sh" \
      bash ./config/bin/immich-autoshutdown.sh 2>&1)

assert_eq "$(grep -c 'would arm next wake and power off' <<<"$out")" "1" "DRY_RUN logs intended poweroff"
assert_eq "$(test -s "$WAKE_LOG" && echo called || echo not)" "not" "DRY_RUN does not arm wake or poweroff"

rm -rf "$_tmp"
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run.sh`
Expected: `FAIL=0`.

- [ ] **Step 5: Write the systemd service**

Create `config/systemd/immich-autoshutdown.service`:

```ini
# Server path: /etc/systemd/system/immich-autoshutdown.service
[Unit]
Description=Immich auto-shutdown guard (powers off when idle past backup window)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/immich-autoshutdown.sh
```

- [ ] **Step 6: Write the systemd timer**

Create `config/systemd/immich-autoshutdown.timer`:

```ini
# Server path: /etc/systemd/system/immich-autoshutdown.timer
[Unit]
Description=Run the Immich auto-shutdown guard every 10 minutes

[Timer]
OnBootSec=15min
OnUnitActiveSec=10min
AccuracySec=1min

[Install]
WantedBy=timers.target
```

- [ ] **Step 7: Commit**

```bash
git add config/bin/immich-autoshutdown.sh config/systemd/immich-autoshutdown.service config/systemd/immich-autoshutdown.timer tests/autoshutdown_test.sh
git commit -m "feat: add auto-shutdown guard script and systemd timer"
```

---

### Task 5: RTC wake scheduler + systemd service

**Files:**
- Create: `config/bin/immich-set-wake.sh`  (server: `/usr/local/bin/immich-set-wake.sh`)
- Create: `config/systemd/immich-wake.service`  (server: `/etc/systemd/system/immich-wake.service`)
- Create: `tests/set_wake_test.sh`

**Interfaces:**
- Produces: `compute_next_wake_epoch <now_epoch> <hour> <min>` — pure, prints the epoch of the next HH:MM strictly after `now` (today if still ahead, else tomorrow). The script's main path writes that epoch to `/sys/class/rtc/rtc0/wakealarm`. Called by the guard (Task 4) and by the systemd service at boot/shutdown.

- [ ] **Step 1: Write the failing tests**

Create `tests/set_wake_test.sh`:

```bash
source ./config/bin/immich-set-wake.sh

# 2026-06-30 08:00:00 local -> next 21:00 is the SAME day at 21:00
now_morning=$(date -d "2026-06-30 08:00:00" +%s)
exp_same=$(date -d "2026-06-30 21:00:00" +%s)
assert_eq "$(compute_next_wake_epoch "$now_morning" 21 0)" "$exp_same" "before 21:00 -> today 21:00"

# 2026-06-30 22:00:00 local -> next 21:00 is the NEXT day
now_late=$(date -d "2026-06-30 22:00:00" +%s)
exp_next=$(date -d "2026-07-01 21:00:00" +%s)
assert_eq "$(compute_next_wake_epoch "$now_late" 21 0)" "$exp_next" "after 21:00 -> tomorrow 21:00"

# exactly at 21:00 -> roll to tomorrow (strictly after now)
now_exact=$(date -d "2026-06-30 21:00:00" +%s)
assert_eq "$(compute_next_wake_epoch "$now_exact" 21 0)" "$exp_next" "exactly 21:00 -> tomorrow"
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL for set_wake cases (function not defined).

- [ ] **Step 3: Implement the wake scheduler**

Create `config/bin/immich-set-wake.sh`:

```bash
#!/usr/bin/env bash
# Server path: /usr/local/bin/immich-set-wake.sh
# Arms the hardware RTC alarm so the PC powers itself on at the next backup time.
# Runs at boot and at shutdown (via immich-wake.service) and from the shutdown guard.
# Pure helper compute_next_wake_epoch is unit-tested; main path writes the wakealarm.
set -euo pipefail

WAKE_HOUR="${WAKE_HOUR:-21}"
WAKE_MIN="${WAKE_MIN:-0}"
RTC="${RTC:-/sys/class/rtc/rtc0/wakealarm}"

# compute_next_wake_epoch <now_epoch> <hour> <min> -> epoch of next HH:MM after now
compute_next_wake_epoch() {
  local now="$1" hour="$2" min="$3"
  local day target
  day=$(date -d "@$now" +%Y-%m-%d)
  target=$(date -d "$day $hour:$min:00" +%s)
  if (( target <= now )); then
    target=$(date -d "$day $hour:$min:00 +1 day" +%s)
  fi
  echo "$target"
}

# Only run the side-effecting main path when executed directly (not when sourced by tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  now=$(date +%s)
  wake_epoch=$(compute_next_wake_epoch "$now" "$WAKE_HOUR" "$WAKE_MIN")
  # The RTC alarm is single-shot; clear then set.
  echo 0    | tee "$RTC" >/dev/null
  echo "$wake_epoch" | tee "$RTC" >/dev/null
  echo "[immich-set-wake] next wake armed for $(date -d "@$wake_epoch")"
fi
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run.sh`
Expected: all set_wake assertions PASS, `FAIL=0`.

- [ ] **Step 5: Write the systemd service (boot + shutdown)**

Create `config/systemd/immich-wake.service`:

```ini
# Server path: /etc/systemd/system/immich-wake.service
# Arms the next RTC wake alarm at boot and again at shutdown, so the alarm is always
# set regardless of how the machine powered off.
[Unit]
Description=Arm RTC wake alarm for next Immich backup window
DefaultDependencies=no
After=sysinit.target
Before=shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/immich-set-wake.sh
ExecStop=/usr/local/bin/immich-set-wake.sh

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 6: Commit**

```bash
git add config/bin/immich-set-wake.sh config/systemd/immich-wake.service tests/set_wake_test.sh
git commit -m "feat: add RTC wake scheduler with next-occurrence logic and tests"
```

---

### Task 6: Manual external-drive export script

**Files:**
- Create: `config/bin/immich-export.sh`  (server: `/usr/local/bin/immich-export.sh`)
- Create: `tests/export_test.sh`

**Interfaces:**
- Consumes: env keys from `/opt/immich/.env` (`UPLOAD_LOCATION`, `DB_USERNAME`, `DB_DATABASE_NAME`), container `immich_postgres`.
- Produces: `build_dump_name <timestamp>` (pure; prints `immich-db-<timestamp>.sql.gz`) and a main path that dumps Postgres + rsync-mirrors photos to `<DEST>/immich-backup/`, then prints a summary. Honors `DRY_RUN=1` (uses `rsync --dry-run`, skips the dump).

- [ ] **Step 1: Write the failing test for the pure helper**

Create `tests/export_test.sh`:

```bash
source ./config/bin/immich-export.sh

assert_eq "$(build_dump_name 20260630-2100)" "immich-db-20260630-2100.sql.gz" "dump name format"
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL for export test (function not defined).

- [ ] **Step 3: Implement the export script**

Create `config/bin/immich-export.sh`:

```bash
#!/usr/bin/env bash
# Server path: /usr/local/bin/immich-export.sh
# Manual, on-demand export of the whole Immich archive to an external USB drive.
# Usage: immich-export.sh /media/<you>/<DRIVE>
# Dumps Postgres (so albums/faces/metadata are restorable), then rsync-mirrors photos.
# Set DRY_RUN=1 to preview (rsync --dry-run, no DB dump).
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/immich/.env}"
PG_CONTAINER="${PG_CONTAINER:-immich_postgres}"

build_dump_name() { echo "immich-db-$1.sql.gz"; }

# main path only when executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  DEST="${1:?Usage: immich-export.sh /path/to/external/drive}"
  [[ -d "$DEST" ]] || { echo "ERROR: destination '$DEST' is not a mounted directory"; exit 1; }

  # shellcheck source=/dev/null
  source "$ENV_FILE"
  : "${UPLOAD_LOCATION:?UPLOAD_LOCATION not set in $ENV_FILE}"

  OUT="$DEST/immich-backup"
  mkdir -p "$OUT"
  ts=$(date +%Y%m%d-%H%M)
  dump_name="$(build_dump_name "$ts")"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[export] DRY_RUN: skipping DB dump"
    rsync -a --dry-run --delete "$UPLOAD_LOCATION/" "$OUT/photos/"
    echo "[export] DRY_RUN complete (no changes written)"
    exit 0
  fi

  echo "[export] dumping database -> $OUT/$dump_name"
  docker exec -t "$PG_CONTAINER" pg_dumpall --clean --if-exists --username="$DB_USERNAME" \
    | gzip > "$OUT/$dump_name"

  echo "[export] mirroring photos -> $OUT/photos/"
  rsync -a --delete --info=stats2 "$UPLOAD_LOCATION/" "$OUT/photos/"

  photo_count=$(find "$OUT/photos" -type f | wc -l)
  total_size=$(du -sh "$OUT" | awk '{print $1}')
  echo "--------------------------------------------"
  echo "[export] DONE"
  echo "  DB dump:     $dump_name"
  echo "  photo files: $photo_count"
  echo "  total size:  $total_size"
  echo "  location:    $OUT"
fi
```

- [ ] **Step 4: Run tests, verify pass**

Run: `bash tests/run.sh`
Expected: export assertion PASS, `FAIL=0`.

- [ ] **Step 5: Syntax-check the script**

Run: `bash -n config/bin/immich-export.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`.

- [ ] **Step 6: Commit**

```bash
git add config/bin/immich-export.sh tests/export_test.sh
git commit -m "feat: add manual external-drive export script with tests"
```

---

### Task 7: Server setup + testing checklists

**Files:**
- Create: `docs/setup/01-install-and-deploy.md`
- Create: `docs/setup/02-bios-rtc-wake.md`
- Create: `docs/setup/03-static-ip-and-tailscale.md`
- Create: `docs/setup/04-android-app.md`
- Create: `docs/setup/05-immich-admin-and-ml-tuning.md`
- Create: `docs/setup/06-on-server-testing.md`

**Interfaces:**
- Consumes: all files from Tasks 2–6 (references their server paths).
- Produces: the human runbook. No code; verification is a completeness check.

- [ ] **Step 1: Write the install/deploy checklist**

Create `docs/setup/01-install-and-deploy.md`:

```markdown
# 01 — Install Docker & Deploy Immich (run on the Debian 13 server)

1. Install Docker Engine + Compose plugin:
   `curl -fsSL https://get.docker.com | sh` then `sudo usermod -aG docker $USER` and re-login.
2. Create the layout:
   `sudo mkdir -p /opt/immich /photos /usr/local/lib/immich`
3. Copy from the authoring machine into place:
   - `config/docker-compose.yml` -> `/opt/immich/docker-compose.yml`
   - `config/.env.example` -> `/opt/immich/.env` (then edit: set a long random `DB_PASSWORD`, correct `TZ`)
   - `config/bin/*.sh` -> `/usr/local/bin/` (`chmod +x`)
   - `config/bin/lib/shutdown-decision.sh` -> `/usr/local/lib/immich/` 
   - `config/systemd/*` -> `/etc/systemd/system/`
4. Start Immich: `cd /opt/immich && docker compose up -d`
5. Open `http://<server-ip>:2283` and create the admin account.
```

- [ ] **Step 2: Write the BIOS RTC wake checklist**

Create `docs/setup/02-bios-rtc-wake.md`:

```markdown
# 02 — BIOS RTC Wake + systemd wake service (run on the Debian 13 server)

1. Reboot into BIOS/UEFI. Find Power Management -> enable
   "Wake on RTC Alarm" / "RTC Alarm Power On" / "Auto Power On". Save & exit.
2. Enable the wake service so the alarm is armed at boot and shutdown:
   `sudo systemctl enable --now immich-wake.service`
3. Verify the alarm is set: `cat /sys/class/rtc/rtc0/wakealarm` (should be a future epoch).
4. FALLBACK if your BIOS has no RTC wake option: use suspend instead of poweroff.
   In `/usr/local/bin/immich-autoshutdown.sh` change `systemctl poweroff` to
   `rtcwake -m mem -t $(/usr/local/bin/immich-set-wake.sh >/dev/null; cat /sys/class/rtc/rtc0/wakealarm)`
   — or simpler, `systemctl suspend` after arming the alarm. Suspend wakes very reliably.
```

- [ ] **Step 3: Write the static IP + Tailscale checklist**

Create `docs/setup/03-static-ip-and-tailscale.md`:

```markdown
# 03 — Static LAN IP + Tailscale (run on the Debian 13 server)

1. Reserve a static LAN IP: in your router's DHCP settings, bind the server's MAC to a
   fixed address (e.g. 192.168.1.50). Confirm with `ip a`.
2. Install Tailscale: `curl -fsSL https://tailscale.com/install.sh | sh`
3. `sudo tailscale up` and authenticate (free personal plan).
4. Note the MagicDNS name (`tailscale status`) — e.g. `immich-server.tailXXXX.ts.net`.
5. On each phone: install the Tailscale app, sign in to the same account, set always-on.
6. No router port-forwarding. Do NOT expose 2283 to the internet.
```

- [ ] **Step 4: Write the Android app checklist**

Create `docs/setup/04-android-app.md`:

```markdown
# 04 — Android Immich app (per phone, 2–3 family members)

1. Install "Immich" from the Play Store. Server URL = the Tailscale MagicDNS name on
   port 2283 (e.g. `http://immich-server.tailXXXX.ts.net:2283`). Log in as that person's
   account (created by admin in doc 05).
2. Settings -> Backup: turn ON automatic backup; select the Camera album.
3. Backup triggers: enable "only while charging" and "only on Wi-Fi" (or unmetered).
4. For other media (WhatsApp, screenshots): add those albums but leave them for manual
   "Back up now", or include them in auto-backup if you want them automatic.
```

- [ ] **Step 5: Write the Immich admin + ML tuning checklist**

Create `docs/setup/05-immich-admin-and-ml-tuning.md`:

```markdown
# 05 — Immich admin setup + ML tuning for old hardware

1. As admin: Administration -> Users -> create 2–3 member accounts (one per person).
2. Administration -> Settings -> Machine Learning: keep Facial Recognition ON and Smart
   Search ON (8 GB RAM handles both). To halve load you may disable Smart Search.
3. Administration -> Settings -> Job Settings: set concurrency = 1 for
   "Face Detection", "Facial Recognition", and "Smart Search" (steady low CPU on the 2-core i3).
4. Expect the FIRST library scan to take several nightly windows; daily new photos are fast.
5. ML container already has a 3 GB memory limit (docker-compose.yml `mem_limit`).
```

- [ ] **Step 6: Write the on-server testing checklist**

Create `docs/setup/06-on-server-testing.md`:

```markdown
# 06 — On-server test plan (validates the whole system)

WAKE
- Arm a near-term alarm: `sudo bash -c 'echo 0 > /sys/class/rtc/rtc0/wakealarm; \
  echo $(( $(date +%s) + 120 )) > /sys/class/rtc/rtc0/wakealarm'` then `sudo poweroff`.
- Expect the PC to power on by itself ~2 min later.

AUTO-SHUTDOWN GUARD (no real poweroff)
- Idle + past window -> intends to power off:
  `sudo DRY_RUN=1 MIN_UPTIME=0 /usr/local/bin/immich-autoshutdown.sh`
  Expect a log line "DRY_RUN: would arm next wake and power off now".
- Active session blocks it: while logged into the desktop, run the same command;
  expect "user_active=1 ... stay user_active".
- Active upload blocks it: start a phone upload, run the same command;
  expect "uploads_active=1 ... stay uploads_active".

BACKUP
- Take a new photo on a phone on Wi-Fi; confirm it appears in Immich within the window.

FACE RECOGNITION
- After a scan, open People; name a person; search by them.

MANUAL EXPORT + RESTORE DRY-RUN
- Plug in USB drive, then: `DRY_RUN=1 /usr/local/bin/immich-export.sh /media/<you>/<DRIVE>`
  (preview), then run without DRY_RUN to write.
- Restore test: on a throwaway dir, `gunzip -c immich-db-*.sql.gz | docker exec -i \
  immich_postgres psql -U immich` against a scratch stack to confirm the dump loads.

REMOTE VIEW
- Disable Wi-Fi on a phone (cellular only); confirm Immich still loads via Tailscale.
```

- [ ] **Step 7: Verify all checklist files exist and are non-empty**

Run: `for f in docs/setup/0*.md; do test -s "$f" && echo "OK $f" || echo "MISSING $f"; done`
Expected: six `OK` lines, no `MISSING`.

- [ ] **Step 8: Commit**

```bash
git add docs/setup
git commit -m "docs: add server setup and on-server testing checklists"
```

---

## Self-Review

**Spec coverage:**
- Immich stack (spec §4 L1) → Task 2. ✓
- RTC self-wake at 21:00 (spec §5.1) → Task 5. ✓
- Conservative auto-shutdown (spec §5.1) → Tasks 3 (logic) + 4 (wiring/timer). ✓
- Backup + catch-up + per-device (spec §5.2) → stock Immich, surfaced in Tasks 4 (app) + 5 (admin) checklists. ✓
- Single-drive storage + manual export (spec §5.3) → Task 6. ✓
- Static IP + Tailscale, no HTTPS/ports (spec §5.4) → Task 7 doc 03. ✓
- Users/devices/ML + restart:always (spec §5.5) → Task 2 (`restart: always`) + Task 7 doc 05. ✓
- ML tuning for old CPU (spec §5.6) → Task 2 (`mem_limit`) + Task 7 doc 05 (concurrency=1). ✓
- Error handling (spec §6) → `restart: always` (Task 2), catch-up + conservative guard (Tasks 3–4). ✓
- Testing plan (spec §7) → Task 7 doc 06 + unit tests across Tasks 1–6. ✓
- Deliverables list (spec §8) → all created across Tasks 2–7. ✓

No gaps.

**Placeholder scan:** No TBD/TODO; every code step contains full content. ✓

**Type/name consistency:** `should_shutdown` (Task 3) signature matches its call in Task 4. `compute_next_wake_epoch` (Task 5) matches its tests. `build_dump_name` (Task 6) matches its test. Container name `immich_postgres` consistent between Task 2 and Task 6. Server paths consistent across tasks and checklists. ✓
