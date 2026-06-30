source ../config/bin/lib/shutdown-decision.sh

# field of the decision string we care about
verb() { awk '{print $1}'; }

assert_eq "$(should_shutdown 600  2700 0 0 | verb)" "stay"     "below min uptime -> stay"
assert_eq "$(should_shutdown 3000 2700 1 0 | verb)" "stay"     "user active -> stay"
assert_eq "$(should_shutdown 3000 2700 0 1 | verb)" "stay"     "uploads active -> stay"
assert_eq "$(should_shutdown 3000 2700 0 0 | verb)" "shutdown" "idle + past window -> shutdown"
assert_eq "$(should_shutdown 2700 2700 0 0 | verb)" "shutdown" "exactly at min uptime -> shutdown"
