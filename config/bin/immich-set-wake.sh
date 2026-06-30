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
  local day tomorrow target
  day=$(date -d "@$now" +%Y-%m-%d)
  target=$(date -d "$day $hour:$min:00" +%s)
  if (( target <= now )); then
    tomorrow=$(date -d "$day +1 day" +%Y-%m-%d)
    target=$(date -d "$tomorrow $hour:$min:00" +%s)
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
