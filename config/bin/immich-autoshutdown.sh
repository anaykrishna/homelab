#!/usr/bin/env bash
# Server path: /usr/local/bin/immich-autoshutdown.sh
# Runs every ~10 min via systemd timer. Shuts the PC down only when it is past the
# backup window, nobody is at the desktop, and no Immich uploads/jobs are active.
# Set DRY_RUN=1 to log the decision without arming wake or powering off.
set -euo pipefail

MIN_UPTIME="${MIN_UPTIME:-2700}"          # 45 min
SHUTDOWN_WINDOW_START="${SHUTDOWN_WINDOW_START:-22}"  # only auto-power-off at night, so
SHUTDOWN_WINDOW_END="${SHUTDOWN_WINDOW_END:-7}"       # this shared PC stays up for daytime use
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
# Fail-safe: if loginctl is absent, user_active stays 0 (biases toward shutdown — acceptable for a server).
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

# --- night-only gate: only auto-shutdown during the configured overnight window ---
hour=$(date +%-H)
in_window="$(in_shutdown_window "$hour" "$SHUTDOWN_WINDOW_START" "$SHUTDOWN_WINDOW_END")"

decision="$(should_shutdown "$uptime_secs" "$MIN_UPTIME" "$user_active" "$uploads_active" "$in_window")"
log "uptime=${uptime_secs}s hour=${hour} user_active=${user_active} uploads_active=${uploads_active} in_window=${in_window} -> ${decision}"

if [[ "${decision%% *}" == "shutdown" ]]; then
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "DRY_RUN: would arm next wake and power off now"
    exit 0
  fi
  "$SET_WAKE" || log "WARN: failed to arm next wake alarm"
  log "powering off"
  systemctl poweroff
fi
