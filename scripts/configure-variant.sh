#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)

case ${1:-core} in
  core) cat "$root/configs/core.config" ;;
  core-honk)
    awk '
      function symbol(line) {
        sub(/^# /, "", line)
        return line ~ /^CONFIG_/ ? substr(line, 1, match(line, /[= ]/) - 1) : ""
      }
      FNR == NR { if (symbol($0) != "") overridden[symbol($0)] = 1; next }
      !(symbol($0) in overridden)
    ' "$root/configs/core-honk.config" "$root/configs/core.config"
    cat "$root/configs/core-honk.config"
    ;;
  *) printf 'Unknown firmware variant: %s\n' "$1" >&2; exit 64 ;;
esac
