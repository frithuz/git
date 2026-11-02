#!/usr/bin/env bash
# Read release identity from the single maintained set of pins.
set -euo pipefail
cd "$(dirname "$0")/.."
value() { awk -F= -v name="$1" 'NF == 2 && $1 == "ARG " name { print $2 }' git.Dockerfile; }
version=$(value VERSION)
revision=$(value PACKAGE_REVISION)
checksum=$(value SHA256)
epoch=$(value SOURCE_DATE_EPOCH)
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ $revision =~ ^[0-9][a-zA-Z0-9.+~]*$ ]]
[[ $checksum =~ ^[0-9a-f]{64}$ ]]
[[ $epoch =~ ^[0-9]+$ ]]
printf 'version=%s\nrevision=%s\npackage_version=1:%s-%s\ntag=v%s-%s\n' \
	"$version" "$revision" "$version" "$revision" "$version" "$revision"
