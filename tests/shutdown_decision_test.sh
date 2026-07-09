source ../config/bin/lib/shutdown-decision.sh

# field of the decision string we care about
verb() { awk '{print $1}'; }

# should_shutdown <uptime> <min_uptime> <user_active> <uploads_active> <in_window>
assert_eq "$(should_shutdown 600  2700 0 0 1 | verb)" "stay"     "below min uptime -> stay"
assert_eq "$(should_shutdown 3000 2700 1 0 1 | verb)" "stay"     "user active -> stay"
assert_eq "$(should_shutdown 3000 2700 0 1 1 | verb)" "stay"     "uploads active -> stay"
assert_eq "$(should_shutdown 3000 2700 0 0 1 | verb)" "shutdown" "idle + in window -> shutdown"
assert_eq "$(should_shutdown 2700 2700 0 0 1 | verb)" "shutdown" "exactly at min uptime + in window -> shutdown"
assert_eq "$(should_shutdown 3000 2700 0 0 0 | verb)" "stay"     "idle but outside shutdown window -> stay"

# in_shutdown_window <hour> <start> <end> -> "1"/"0"; overnight window wraps (start > end)
assert_eq "$(in_shutdown_window 23 22 7)" "1" "23:00 inside overnight window"
assert_eq "$(in_shutdown_window 2  22 7)" "1" "02:00 inside overnight window"
assert_eq "$(in_shutdown_window 22 22 7)" "1" "start hour is inside (inclusive)"
assert_eq "$(in_shutdown_window 7  22 7)" "0" "end hour is outside (exclusive)"
assert_eq "$(in_shutdown_window 14 22 7)" "0" "14:00 (midday) outside overnight window"
# non-wrapping window (start < end)
assert_eq "$(in_shutdown_window 3 1 5)" "1" "03:00 inside non-wrapping window"
assert_eq "$(in_shutdown_window 6 1 5)" "0" "06:00 outside non-wrapping window"
