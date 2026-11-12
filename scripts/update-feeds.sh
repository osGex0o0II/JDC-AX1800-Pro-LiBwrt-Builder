#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "${OPENWRT_PATH:-openwrt}"
cp "$root/deps/feeds.conf" feeds.conf

./scripts/feeds update -a
while read -r kind name url; do
  expected=${url##*^}
  [[ $kind == src-git && $expected =~ ^[0-9a-f]{40}$ ]]
  actual=$(git -C "feeds/$name" rev-parse HEAD)
  if [[ $actual != "$expected" ]]; then
    printf 'Feed %s: expected %s, got %s\n' "$name" "$expected" "$actual" >&2
    exit 1
  fi
done < feeds.conf

while read -r _ name _; do
  [[ $name == vikingfy ]] || ./scripts/feeds install -a -p "$name"
done < feeds.conf
