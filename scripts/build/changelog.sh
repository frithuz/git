#!/usr/bin/env bash
set -euo pipefail
date=$(date -u -d "@${SOURCE_DATE_EPOCH:?}" -R)
cat >"${1:?Pass the changelog destination}" <<EOF
git (1:${VERSION:?}-${PACKAGE_REVISION:?}) trixie; urgency=medium

  * Build upstream Git with the shared Frithuz recipe.

 -- Jonathan Garbee <jonathan@garbee.me>  $date
EOF
