#!/usr/bin/env bash
set -euo pipefail

image=${1:?sysupgrade image required}
prefix=sysupgrade-jdcloud_re-ss-01
members=$(tar -tf "$image")
for name in CONTROL kernel root; do
  count=$(awk -v member="$prefix/$name" '$0 == member { count++ } END { print count+0 }' <<< "$members")
  [[ $count == 1 ]] || { printf 'Expected one %s/%s in sysupgrade image\n' "$prefix" "$name" >&2; exit 1; }
done
kernel_bytes=$(tar -xOf "$image" "$prefix/kernel" | wc -c)
if (( kernel_bytes == 0 || kernel_bytes > 12 * 1024 * 1024 )); then
  printf 'Kernel size %s bytes does not fit the JDC 12 MiB HLOS slot\n' "$kernel_bytes" >&2
  exit 1
fi
