#!/usr/bin/env bash
# Server path: /usr/local/lib/immich/shutdown-decision.sh
# Pure decision logic for the auto-shutdown guard. No side effects — unit-testable.

# in_shutdown_window <hour> <start_hour> <end_hour> -> prints "1" if hour is in the
# [start, end) shutdown window, else "0". When start > end the window wraps past
# midnight (e.g. 22..7 means 22:00–06:59). This gates auto-shutdown to night-time on a
# machine that is also used during the day.
in_shutdown_window() {
  local hour="$1" start="$2" end="$3"
  if (( start <= end )); then
    (( hour >= start && hour < end )) && echo 1 || echo 0
  else
    (( hour >= start || hour < end )) && echo 1 || echo 0
  fi
}

# should_shutdown <uptime_secs> <min_uptime_secs> <user_active:0|1> <uploads_active:0|1> <in_window:0|1>
# Prints "shutdown <reason>" or "stay <reason>".
should_shutdown() {
  local uptime_secs="$1" min_uptime="$2" user_active="$3" uploads_active="$4" in_window="$5"

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
  if (( in_window == 0 )); then
    echo "stay outside_shutdown_window"
    return 0
  fi
  echo "shutdown idle_and_past_window"
  return 0
}
