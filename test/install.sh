#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Installation test failed at line $LINENO" >&2' ERR
export DEBIAN_FRONTEND=noninteractive
# Match a local machine's documentation install rather than the slim image's exclusions.
rm -f /etc/dpkg/dpkg.cfg.d/docker
sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources
apt-get -o Acquire::https::CaInfo=/etc/ssl/certs/ca-certificates.crt -o APT::Update::Error-Mode=any update
# First exercise a normal upgrade from Debian's own package.
apt-get -o Acquire::https::CaInfo=/etc/ssl/certs/ca-certificates.crt install -y --no-install-recommends \
	git ca-certificates
before=$(dpkg-query -W -f '${Version}' git)
apt-get install -y --no-install-recommends /packages/*.deb
after=$(dpkg-query -W -f '${Version}' git)
dpkg --compare-versions "$after" gt "$before"
bash /mnt/src/test/smoke.sh
cmp /usr/bin/git /artifact/usr/bin/git
cmp /usr/lib/git-core/git-remote-http /artifact/usr/lib/git-core/git-remote-http
[[ -f /usr/share/doc/git/copyright ]]
[[ -f /usr/share/doc/git/build-info/build/git.Dockerfile ]]
[[ -f /usr/share/doc/git/build-info/SOURCE-PACKAGE ]]
apt-get remove -y git
[[ ! -e /usr/bin/git ]]
[[ ! -e /usr/lib/git-core/git-remote-http ]]
# Exercise the scratch tree in the same clean runtime after removing the package.
cp -a /artifact/. /
bash /mnt/src/test/smoke.sh
printf 'Package upgrade, removal, and artifact smoke tests passed\n' >/verified
