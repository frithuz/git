#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
while IFS= read -r -d '' file; do
	bash -n "$file"
	shellcheck "$file"
done < <(find scripts test -type f -name '*.sh' -print0)
hadolint git.Dockerfile
actionlint
python3 test/openbao.py
bash scripts/metadata.sh
docker buildx bake --print >/dev/null
