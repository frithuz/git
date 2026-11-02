#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export GNUPGHOME
GNUPGHOME=$(mktemp -d)
trap 'rm -rf "$GNUPGHOME"' EXIT
gpg --batch --pinentry-mode loopback --passphrase '' \
	--quick-generate-key 'Repository test <test@example.invalid>' ed25519 sign 0
APT_SIGNING_KEY=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
export APT_SIGNING_KEY
export APT_ARCHITECTURES
native=$(dpkg --print-architecture)
APT_ARCHITECTURES=${APT_ARCHITECTURES:-$native}
bash /usr/local/lib/git-build/apt.sh /input /source /repository
for architecture in $APT_ARCHITECTURES; do
	indexed=$(awk '$1 == "Architecture:" { print $2 }' "/repository/dists/trixie/main/binary-$architecture/Packages")
	[[ $indexed == "$architecture" ]]
done
cp /repository/key.asc /etc/apt/keyrings/git-test.asc
cat >/etc/apt/sources.list.d/git-test.sources <<EOF
Types: deb deb-src
URIs: file:/repository
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/git-test.asc
EOF
apt-get update
rm -f /etc/dpkg/dpkg.cfg.d/docker
apt-get install -y --no-install-recommends git
[[ $(dpkg-query -W -f '${Version}' git) == "1:${VERSION:?}-"* ]]
bash /tests/smoke.sh

# apt source must retrieve the same .dsc identified by the installed binary.
download=$(mktemp -d)
cd "$download"
version=$(dpkg-query -W -f '${Version}' git)
apt-get source --download-only "git=$version"
dscs=(*.dsc)
[[ ${#dscs[@]} == 1 && -f ${dscs[0]} ]]
expected=$(sed -n 's/^sha256: //p' /usr/share/doc/git/build-info/SOURCE-PACKAGE)
printf '%s  %s\n' "$expected" "${dscs[0]}" | sha256sum --check --strict
dpkg-source --extract "${dscs[0]}" extracted
[[ -f extracted/debian/rules && -f extracted/zlib-ng/zlib-ng.h.in ]]
[[ ! -e extracted/rust-std ]]
[[ -f extracted/debian/upstream/rust/COPYRIGHT-library.html ]]
[[ -f extracted/debian/upstream/rust/licenses/MIT.txt ]]
cmp extracted/debian/recipe/scripts/build/git.sh /usr/share/doc/git/build-info/build/scripts/build/git.sh

# Matching version strings alone must not allow publishing a different source descriptor.
cp -a /source mismatched-source
while IFS= read -r -d '' file; do
	printf '\nX-Test: different source descriptor\n' >>"$file"
done < <(find mismatched-source -name '*.dsc' -print0)
if bash /usr/local/lib/git-build/apt.sh /input "$download/mismatched-source" /mismatched-repository \
	>/tmp/mismatched.log 2>&1; then
	echo 'Repository accepted source that does not match the binaries' >&2
	exit 1
fi
grep -F 'Source package does not match the source digest recorded by' /tmp/mismatched.log

# An altered index must be rejected even though the public signing key is trusted.
printf '\ntampered\n' >>"/repository/dists/trixie/main/binary-$native/Packages"
gzip -n -9 -c "/repository/dists/trixie/main/binary-$native/Packages" \
	>"/repository/dists/trixie/main/binary-$native/Packages.gz"
rm -rf /var/lib/apt/lists/*
# Isolate this negative check from unrelated Debian mirrors or network failures.
if apt-get update -o APT::Update::Error-Mode=any \
	-o Dir::Etc::sourcelist=/etc/apt/sources.list.d/git-test.sources \
	-o Dir::Etc::sourceparts=- >/tmp/tampered.log 2>&1; then
	cat /tmp/tampered.log >&2
	echo 'APT accepted a modified repository index' >&2
	exit 1
fi
log=$(cat /tmp/tampered.log)
if [[ $log != *'Hash Sum mismatch'* && $log != *'File has unexpected size'* ]]; then
	cat /tmp/tampered.log >&2
	echo 'APT failed for a reason other than the altered index checksum' >&2
	exit 1
fi
printf 'Signed APT installation and tamper rejection passed\n' >/verified
