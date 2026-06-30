# 02 — BIOS RTC Wake + systemd wake service (run on the Ubuntu server)

1. Reboot into BIOS/UEFI. Find Power Management -> enable
   "Wake on RTC Alarm" / "RTC Alarm Power On" / "Auto Power On". Save & exit.
2. Enable the wake service so the alarm is armed at boot and shutdown:
   `sudo systemctl enable --now immich-wake.service`
3. Verify the alarm is set: `cat /sys/class/rtc/rtc0/wakealarm` (should be a future epoch).
4. FALLBACK if your BIOS has no RTC wake option: use suspend instead of poweroff.
   In `/usr/local/bin/immich-autoshutdown.sh` change `systemctl poweroff` to `systemctl suspend`.
   The wake service's ExecStop (and the guard's set-wake call) already arm the RTC alarm before suspend,
   and the kernel RTC alarm wakes reliably from suspend.
