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
