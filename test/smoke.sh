#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Git smoke test failed at line $LINENO" >&2' ERR

[[ $(command -v git) == /usr/bin/git ]]
[[ $(git --version) == "git version ${VERSION:?}" ]]
[[ $(git --exec-path) == /usr/lib/git-core ]]
options=$(git version --build-options)
[[ $options == *"zlib-ng: ${ZLIB_NG_VERSION:?}"* ]]
[[ $options == *'non-collision-detecting-SHA-1: SHA1_OPENSSL_UNSAFE'* ]]
for file in /usr/bin/git /usr/lib/git-core/git-remote-http; do
	dependencies=$(ldd "$file")
	[[ $dependencies != *'not found'* ]]
done
for command in daemon http-backend http-push imap-send instaweb send-email svn p4; do
	[[ ! -e /usr/lib/git-core/git-$command ]]
done
[[ ! -e /usr/bin/git-shell ]]
[[ ! -e /usr/bin/git-cvsserver ]]
[[ -f /etc/ssl/certs/ca-certificates.crt ]]

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
git init -q "$work/repo"
cd "$work/repo"
git config user.name 'Build test'
git config user.email test@example.invalid
printf 'needle\n' >file
git add file
git commit -qm initial
git grep -qP 'ne{2}dle'
git clone -q --no-local . "$work/clone"
git -C "$work/clone" fsck --strict
git -C "$work/clone" gc
[[ $(git -C "$work/clone" show HEAD:file) == needle ]]
git subtree add --prefix=vendor "$work/clone" HEAD -m subtree
[[ $(cat vendor/file) == needle ]]
# Confirm the compiled system config location without modifying host configuration.
origin=$(env -u GIT_CONFIG_NOSYSTEM git config --system --list --show-origin 2>&1 || true)
[[ $origin == *'/etc/gitconfig'* ]]
echo "Git $VERSION smoke tests passed on $(dpkg --print-architecture)"
