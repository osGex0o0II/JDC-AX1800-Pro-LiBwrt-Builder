#!/bin/sh
# CoreMark CPU benchmark — runs once on first boot, caches result

BENCH_LOG="/etc/bench.log"
BENCH_LOCK="/tmp/.coremark_done"

[ -f "$BENCH_LOCK" ] && exit 0

if [ ! -f "$BENCH_LOG" ]; then
  COREMARK_RESULT=$(coremark 2>/dev/null | grep -oP 'Iterations/Sec:\s*\K[0-9.]+' || echo "N/A")
  echo "CoreMark Score: $COREMARK_RESULT Iterations/Sec" > "$BENCH_LOG"
fi

touch "$BENCH_LOCK"
exit 0
