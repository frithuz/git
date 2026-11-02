#!/usr/bin/env bash
# Run with Docker --network=none to prove a downloaded .dsc rebuilds from its own inputs.
set -euo pipefail
trap 'echo "Debian source rebuild failed at line $LINENO" >&2' ERR
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp /source-package/* "$work/"
dpkg-source --extract "$work"/*.dsc "$work/git"
[[ ! -e $work/git/rust-std ]]
[[ -f $work/git/debian/upstream/rust/COPYRIGHT-library.html ]]
cd "$work/git"
chown -R 65534:65534 "$work"
runuser -u nobody -- dpkg-buildpackage --build=binary --no-sign --no-check-builddeps
rm -f /etc/dpkg/dpkg.cfg.d/docker
dpkg --install "$work"/*.deb
script_sha=$(sha256sum debian/recipe/scripts/build/git.sh | cut -d' ' -f1)
grep -Fx "build-script: scripts/build/git.sh sha256:$script_sha" /usr/share/doc/git/build-info/SOURCE
dsc_sha=$(sha256sum "$work"/*.dsc | cut -d' ' -f1)
grep -Fx "sha256: $dsc_sha" /usr/share/doc/git/build-info/SOURCE-PACKAGE
bash /mnt/src/test/smoke.sh
printf 'Offline Debian source-package rebuild and smoke tests passed\n' >/source-verified
