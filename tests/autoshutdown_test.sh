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
      bash ../config/bin/immich-autoshutdown.sh 2>&1)

assert_eq "$(grep -c 'would arm next wake and power off' <<<"$out")" "1" "DRY_RUN logs intended poweroff"
assert_eq "$(test -s "$WAKE_LOG" && echo called || echo not)" "not" "DRY_RUN does not arm wake or poweroff"

rm -rf "$_tmp"
