#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077
: "${APT_SIGNING_KEY:?Set the SIGNING_KEY variable in the apt GitHub environment to the signing-key fingerprint}"
if [[ ! $APT_SIGNING_KEY =~ ^([[:xdigit:]]{40}|[[:xdigit:]]{64})$ ]]; then
	echo 'The apt SIGNING_KEY variable must contain a full OpenPGP fingerprint' >&2
	exit 1
fi
export GNUPGHOME
GNUPGHOME=$(mktemp -d)
trap 'gpgconf --kill all || true; rm -rf "$GNUPGHOME"' EXIT
bash scripts/apt/openbao.sh "$GNUPGHOME/private-key.asc"
gpg --batch --import "$GNUPGHOME/private-key.asc"
rm "$GNUPGHOME/private-key.asc"
export APT_PASSPHRASE_FILE=$GNUPGHOME/passphrase
# CI keys are deliberately unencrypted; prevent any interactive pinentry.
: >"$APT_PASSPHRASE_FILE"
bash scripts/apt/build.sh dist/packages dist/sources-release dist/apt
