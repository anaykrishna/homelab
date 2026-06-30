source ../config/bin/immich-set-wake.sh

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
