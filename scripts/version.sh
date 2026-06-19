#!/bin/bash
# version.sh - Auto-generate version info for ExcaliburOS

BUILD_DATE=$(date +%Y.%m.%d)
BUILD_YEAR=$(date +%Y)
BUILD_MONTH=$(date +%m)
EXCALIBUR_VERSION="${BUILD_YEAR:2}.${BUILD_MONTH}.${GITHUB_RUN_NUMBER:-0}"

GIT_COMMIT="${SOURCE_COMMIT:-unknown}"

cat > version.json << EOF
{
  "version": "$EXCALIBUR_VERSION",
  "build_date": "$BUILD_DATE",
  "git_commit": "$GIT_COMMIT"
}
EOF

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "EXCALIBUR_VERSION=$EXCALIBUR_VERSION" >> "$GITHUB_ENV"
  echo "BUILD_DATE=$BUILD_DATE" >> "$GITHUB_ENV"
  echo "SOURCE_COMMIT=$GIT_COMMIT" >> "$GITHUB_ENV"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "EXCALIBUR_VERSION=$EXCALIBUR_VERSION" >> "$GITHUB_OUTPUT"
fi
