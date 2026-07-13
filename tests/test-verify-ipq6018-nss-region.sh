#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="${ROOT_DIR}/scripts/verify-ipq6018-nss-region.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

write_patch() {
  local path="$1"
  local soc="$2"
  local size="$3"

  mkdir -p "$(dirname "$path")"
  printf '%s\n' \
    "--- a/arch/arm64/boot/dts/qcom/${soc}.dtsi" \
    "+++ b/arch/arm64/boot/dts/qcom/${soc}.dtsi" \
    '@@ -1,3 +1,8 @@' \
    '+  reserved-memory {' \
    '+    nss_region: memory@40000000 {' \
    "+      reg = <0x0 0x40000000 0x0 ${size}>;" \
    '+      no-map;' \
    '+    };' \
    '+  };' >"$path"
}

write_multifile_spoof_patch() {
  local path="$1"

  mkdir -p "$(dirname "$path")"
  printf '%s\n' \
    '--- a/arch/arm64/boot/dts/qcom/ipq6018.dtsi' \
    '+++ b/arch/arm64/boot/dts/qcom/ipq6018.dtsi' \
    '@@ -1 +1 @@' \
    '+  model = "unrelated IPQ6018 change";' \
    '--- a/arch/arm64/boot/dts/qcom/ipq5018.dtsi' \
    '+++ b/arch/arm64/boot/dts/qcom/ipq5018.dtsi' \
    '@@ -1,3 +1,8 @@' \
    '+  reserved-memory {' \
    '+    nss_region: memory@40000000 {' \
    '+      reg = <0x0 0x40000000 0x0 0x01000000>;' \
    '+      no-map;' \
    '+    };' \
    '+  };' >"$path"
}

run_verifier() {
  local patch_dir="$1"
  "$VERIFIER" "$patch_dir" >"${TMP_DIR}/stdout" 2>"${TMP_DIR}/stderr"
}

test -x "$VERIFIER" || fail "NSS verifier is missing or not executable: ${VERIFIER}"

case_dir="${TMP_DIR}/other-soc-first"
write_patch "${case_dir}/001-ipq5018.patch" ipq5018 0x1000000
write_patch "${case_dir}/999-ipq6018.patch" ipq6018 0x01000000
run_verifier "$case_dir" || fail "IPQ5018 candidate shadowed the valid IPQ6018 patch"

case_dir="${TMP_DIR}/short-hex"
write_patch "${case_dir}/001-ipq6018.patch" ipq6018 0x1000000
run_verifier "$case_dir" || fail "equivalent short 16 MiB hexadecimal form was rejected"

case_dir="${TMP_DIR}/wrong-size"
write_patch "${case_dir}/001-ipq6018.patch" ipq6018 0x02000000
if run_verifier "$case_dir"; then
  fail "incorrect 32 MiB IPQ6018 region was accepted"
fi
grep -Fq '16 MiB NSS reserved-memory region' "${TMP_DIR}/stderr" \
  || fail "wrong-size failure did not explain the NSS region requirement"

case_dir="${TMP_DIR}/missing-ipq6018"
write_patch "${case_dir}/001-ipq5018.patch" ipq5018 0x01000000
if run_verifier "$case_dir"; then
  fail "non-IPQ6018 patch was accepted as the device NSS patch"
fi

case_dir="${TMP_DIR}/multifile-spoof"
write_multifile_spoof_patch "${case_dir}/001-multifile.patch"
if run_verifier "$case_dir"; then
  fail "NSS region from another DTS section was attributed to IPQ6018"
fi

grep -Fq 'verify-ipq6018-nss-region.sh' "${ROOT_DIR}/scripts/diy.sh" \
  || fail "diy.sh does not use the shared NSS verifier"
grep -Fq 'verify-ipq6018-nss-region.sh' "${ROOT_DIR}/.github/workflows/build.yml" \
  || fail "build workflow does not use the shared NSS verifier"

echo "PASS: IPQ6018 NSS reserved-memory verification"
