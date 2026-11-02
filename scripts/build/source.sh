#!/usr/bin/env bash
# Make a conventional, architecture-independent multi-component Debian source package.
set -euo pipefail
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p /sources
tree=$work/git-${VERSION:?}
cp /source-inputs/git-"$VERSION".tar.xz "/sources/git_$VERSION.orig.tar.xz"
cp /source-inputs/zlib-ng.tar.gz "/sources/git_$VERSION.orig-zlib-ng.tar.gz"

mkdir "$tree"
tar -xJf "/sources/git_$VERSION.orig.tar.xz" --strip-components=1 -C "$tree"
mkdir "$tree/zlib-ng"
tar -xzf "/sources/git_$VERSION.orig-zlib-ng.tar.gz" --strip-components=1 -C "$tree/zlib-ng"
cp -a /recipe/debian "$tree/"
rust_version=$(rustc --version | awk '{ print $2 }')
[[ $rust_version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]
rust_next=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))
sed -i "s/rustc, cargo/rustc (>= $rust_version), rustc (<< $rust_next), cargo/" "$tree/debian/control"
cp -a /recipe "$tree/debian/recipe"
chmod 0755 "$tree/debian/rules"
mkdir -p "$tree/debian/upstream"
cp -a /out/legal/attribution/git/rust "$tree/debian/upstream/rust"
cp /source-inputs/signer.gpg /source-inputs/git-"$VERSION".tar.sign "$tree/debian/upstream/"
printf 'debian/upstream/signer.gpg\ndebian/upstream/git-%s.tar.sign\n' "$VERSION" \
	>"$tree/debian/source/include-binaries"
cp /out/legal/attribution/git/SOURCE "$tree/debian/upstream/"
sed '/^architecture:/d' /out/legal/attribution/git/VERSION >"$tree/debian/upstream/VERSION"
cp /out/legal/attribution/git/build/ORIGIN "$tree/debian/upstream/"
bash /recipe/scripts/build/changelog.sh "$tree/debian/changelog"
for name in VERSION SHA256 SIGNER ZLIB_NG_VERSION ZLIB_NG_COMMIT ZLIB_NG_SHA256 PACKAGE_REVISION SOURCE_DATE_EPOCH; do
	printf '%s=%q\n' "$name" "${!name}"
done >"$tree/debian/build.env"
printf 'RUSTC_VERSION=%q\n' "$(rustc --version)" >>"$tree/debian/build.env"

# Work beside the original archives so dpkg-source preserves their exact downloaded bytes.
mv "$tree" /sources/
cd /sources
dpkg-source --build "git-$VERSION"
rm -rf "git-$VERSION"
dsc="git_${VERSION}-${PACKAGE_REVISION:?}.dsc"
{
	printf 'source-package: git\nversion: 1:%s-%s\ndsc: %s\n' "$VERSION" "$PACKAGE_REVISION" "$dsc"
	printf 'sha256: %s\n' "$(sha256sum "$dsc" | cut -d' ' -f1)"
} >/out/legal/attribution/git/SOURCE-PACKAGE
