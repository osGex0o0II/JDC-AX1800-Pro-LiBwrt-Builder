#!/bin/sh
# CoreMark CPU benchmark - runs once on first boot and caches the result.

BENCH_LOG="/etc/bench.log"
BENCH_LOCK="/tmp/.coremark_done"

[ -f "$BENCH_LOCK" ] && exit 0

if [ -x /bin/coremark ]; then
  COREMARK_BIN="/bin/coremark"
else
  COREMARK_BIN="$(command -v coremark 2>/dev/null || true)"
fi

if [ -n "$COREMARK_BIN" ] && { [ ! -s "$BENCH_LOG" ] || grep -q "N/A" "$BENCH_LOG" 2>/dev/null; }; then
  COREMARK_RESULT="$(
    "$COREMARK_BIN" 2>/dev/null |
      awk -F: '/Iterations\/Sec/ {
        gsub(/^[ \t]+|[ \t]+$/, "", $2)
        print $2
        exit
      }'
  )"

  if [ -n "$COREMARK_RESULT" ]; then
    echo "CoreMark Score: $COREMARK_RESULT Iterations/Sec" > "$BENCH_LOG"
  fi
fi

touch "$BENCH_LOCK"
exit 0
