#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${APT_SIGNING_KEY:?Set the signing key fingerprint}"
: "${APT_GNUPGHOME:?Set the absolute path of the GnuPG directory containing your signing key}"
[[ $APT_GNUPGHOME == /* && -d $APT_GNUPGHOME ]]
[[ ! -e dist/apt ]]
signing_options=(-e APT_SIGNING_KEY)
if [[ -n ${APT_PASSPHRASE_FILE:-} ]]; then
	signing_options+=(--mount "type=bind,source=$APT_PASSPHRASE_FILE,target=/run/secrets/apt-passphrase,readonly"
		-e APT_PASSPHRASE_FILE=/run/secrets/apt-passphrase)
fi
docker buildx build -f git.Dockerfile --target repository-tools --load -t git-repository-tools:local .
docker run --rm \
	--mount "type=bind,source=$PWD/dist/deb,target=/input,readonly" \
	--mount "type=bind,source=$PWD/dist/sources,target=/source,readonly" \
	--mount "type=bind,source=$PWD/dist,target=/output" \
	--mount "type=bind,source=$APT_GNUPGHOME,target=/signing-home,readonly" \
	"${signing_options[@]}" \
	git-repository-tools:local bash /usr/local/lib/git-build/local-sign.sh /input /source /output/apt
