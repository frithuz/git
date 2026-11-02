#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
version=$(awk -F= 'NF == 2 && $1 == "ARG VERSION" { print $2 }' git.Dockerfile)
zlib_ng_version=$(awk -F= 'NF == 2 && $1 == "ARG ZLIB_NG_VERSION" { print $2 }' git.Dockerfile)
docker buildx build -f git.Dockerfile --target repository-tools --load -t git-repository-tools:local .
docker run --rm \
	--mount "type=bind,source=$PWD/dist/deb,target=/input,readonly" \
	--mount "type=bind,source=$PWD/dist/sources,target=/source,readonly" \
	--mount "type=bind,source=$PWD/test,target=/tests,readonly" \
	-e "VERSION=$version" -e "ZLIB_NG_VERSION=$zlib_ng_version" \
	-e 'APT_ARCHITECTURES=amd64 arm64' \
	git-repository-tools:local bash /tests/apt.sh
