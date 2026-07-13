#!/usr/bin/env bash
set -euo pipefail

PATCH_DIR="${1:-}"
[ -n "$PATCH_DIR" ] && [ -d "$PATCH_DIR" ] || {
  echo "ERROR: IPQ6018 kernel patch directory is missing: ${PATCH_DIR:-<unset>}" >&2
  exit 1
}

found_ipq6018_nss_patch=0
for nss_patch in "$PATCH_DIR"/*.patch; do
  [ -f "$nss_patch" ] || continue

  if awk '
    /^\+\+\+[[:space:]]+/ {
      in_ipq6018 = ($0 ~ /^\+\+\+[[:space:]]+b\/arch\/arm64\/boot\/dts\/qcom\/ipq6018\.dtsi([[:space:]]|$)/)
      in_nss_region = 0
      next
    }
    in_ipq6018 && /^\+[[:space:]]*nss_region:[[:space:]]+memory@40000000[[:space:]]*\{/ {
      in_nss_region = 1
      found_nss_region = 1
      next
    }
    in_ipq6018 && in_nss_region && /^\+[[:space:]]*reg[[:space:]]*=[[:space:]]*<0x0[[:space:]]+0x40000000[[:space:]]+0x0[[:space:]]+0x0*1000000>[[:space:]]*;/ {
      found_16_mib_reg = 1
    }
    in_ipq6018 && in_nss_region && /^\+[[:space:]]*};/ {
      closed_nss_region = 1
      in_nss_region = 0
    }
    END {
      if (found_nss_region && found_16_mib_reg && closed_nss_region) exit 0
      if (found_nss_region) exit 2
      exit 1
    }
  ' "$nss_patch"; then
    echo "OK: independent 16 MiB NSS reserved-memory region verified for IPQ6018"
    exit 0
  elif [ "$?" -eq 2 ]; then
    found_ipq6018_nss_patch=1
  fi
done

if [ "$found_ipq6018_nss_patch" -eq 1 ]; then
  echo "ERROR: independent 16 MiB NSS reserved-memory region is missing from the IPQ6018 patch" >&2
else
  echo "ERROR: IPQ6018 NSS reserved-memory patch was not found in ${PATCH_DIR}" >&2
fi
exit 1
