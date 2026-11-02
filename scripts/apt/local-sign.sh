#!/usr/bin/env bash
# Keep GnuPG sockets and locks on the container filesystem, including on macOS hosts.
set -euo pipefail
umask 077
export GNUPGHOME
GNUPGHOME=$(mktemp -d)
trap 'gpgconf --kill all || true; rm -rf "$GNUPGHOME"' EXIT
tar -C /signing-home --exclude='S.*' --exclude='*.lock' --exclude='.#lk*' -cf - . |
	tar --no-same-owner --no-same-permissions -C "$GNUPGHOME" -xf -
bash /usr/local/lib/git-build/apt.sh "$@"
