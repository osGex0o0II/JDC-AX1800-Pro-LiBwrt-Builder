#!/bin/bash
# version.sh - Auto-generate version info for JDC AX1800 Pro LiBwrt

BUILD_DATE="${FILE_DATE:-${BUILD_DATE:-$(date +%Y.%m.%d)}}"
BUILD_YEAR="${BUILD_DATE%%.*}"
BUILD_MONTH="${BUILD_DATE#*.}"
BUILD_MONTH="${BUILD_MONTH%%.*}"
FIRMWARE_VERSION="${BUILD_YEAR:2}.${BUILD_MONTH}.${GITHUB_RUN_NUMBER:-0}"

GIT_COMMIT="${SOURCE_COMMIT:-unknown}"

cat > version.json << EOF
{
  "version": "$FIRMWARE_VERSION",
  "build_date": "$BUILD_DATE",
  "git_commit": "$GIT_COMMIT"
}
EOF

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "FIRMWARE_VERSION=$FIRMWARE_VERSION" >> "$GITHUB_ENV"
  echo "BUILD_DATE=$BUILD_DATE" >> "$GITHUB_ENV"
  echo "SOURCE_COMMIT=$GIT_COMMIT" >> "$GITHUB_ENV"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "FIRMWARE_VERSION=$FIRMWARE_VERSION" >> "$GITHUB_OUTPUT"
fi
