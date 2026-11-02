#!/usr/bin/env bash
# Called only by the tag workflow, after both native builds and APT signing succeed.
set -euo pipefail
metadata=$(bash scripts/metadata.sh)
version=$(awk -F= '$1 == "version" { print $2 }' <<<"$metadata")
revision=$(awk -F= '$1 == "revision" { print $2 }' <<<"$metadata")
tag=$(awk -F= '$1 == "tag" { print $2 }' <<<"$metadata")
image="ghcr.io/${REPOSITORY,,}"
auth=$(mktemp -d)
trap 'rm -rf "$auth"' EXIT
export REGISTRY_AUTH_FILE=$auth/auth.json
printf '%s' "${GH_TOKEN:?}" | skopeo login --authfile "$REGISTRY_AUTH_FILE" \
	--username "${GITHUB_ACTOR:?}" --password-stdin ghcr.io
printf '%s' "$GH_TOKEN" | docker login ghcr.io --username "$GITHUB_ACTOR" --password-stdin
for architecture in amd64 arm64; do
	skopeo copy --all "oci-archive:dist/builds/git-$architecture/git.oci.tar" \
		"docker://$image:$version-$revision-$architecture"
done
docker buildx imagetools create \
	--tag "$image:$version-$revision" --tag "$image:$version" \
	"$image:$version-$revision-amd64" "$image:$version-$revision-arm64"
cat >dist/release-notes.md <<EOF
Git $version, package revision $revision, for Debian Trixie.

- Debian packages: amd64 and arm64, both named git.
- OCI artifact: \`$image:$version-$revision\`; copy \`/out/\` into a Trixie image.
- APT repository: extract apt-repository.tar.gz onto an HTTPS static host.
- Debian source package: the .dsc, all .orig archives, and .debian.tar.xz attached below.
- Enable deb-src for this repository and use apt source git to retrieve matching source.
- See README.md for signing-key verification, dependencies, and installation.
EOF
gh release create "$tag" --verify-tag --title "Git $version ($revision)" \
	--notes-file dist/release-notes.md dist/release/*
