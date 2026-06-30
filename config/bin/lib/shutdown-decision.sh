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
