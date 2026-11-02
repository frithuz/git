#!/usr/bin/env bash
set -euo pipefail

legal=/out/legal/attribution/git
[[ $(awk '$1 == "sha256:" { print $2 }' "$legal/SOURCE") == "${SHA256:?}" ]]
cp -a /recipe "$legal/build"
printf 'revision: %s\nrepository: %s\n' "${REVISION:?}" "${REPOSITORY_URL:?}" >"$legal/build/ORIGIN"
printf 'upstream: %s\npackage: 1:%s-%s\narchitecture: %s\n' \
	"${VERSION:?}" "$VERSION" "${PACKAGE_REVISION:?}" "$(dpkg --print-architecture)" >"$legal/VERSION"

# Publish the exact verified archives and recipe alongside both binary formats.
# Keyservers reorder ASCII armor headers; retain the verified key packets canonically.
gpg --batch --yes --dearmor --output /source-inputs/signer.gpg /source-inputs/signer.asc
rm /source-inputs/signer.asc
bash /recipe/scripts/build/source.sh
