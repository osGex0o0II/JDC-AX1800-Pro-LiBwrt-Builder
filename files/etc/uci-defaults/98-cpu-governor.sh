#!/bin/sh
# Set CPU governor to performance for consistent routing throughput

GOVERNOR="performance"
for CPU in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
  [ -f "$CPU" ] && echo "$GOVERNOR" > "$CPU" 2>/dev/null
done

exit 0
