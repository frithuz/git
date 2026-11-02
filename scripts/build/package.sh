#!/usr/bin/env bash
set -euo pipefail

package_version="1:${VERSION:?}-${PACKAGE_REVISION:?}"
architecture=$(dpkg --print-architecture)
root=${PACKAGE_WORK_ROOT:-/package-root}
output=${PACKAGE_OUTPUT:-/packages}
recipe=${PACKAGE_CONTROL_ROOT:-/recipe}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$root/DEBIAN" "$root/usr/share/doc/git" "$output"
cp -a "${GIT_OUTPUT:-/out}/usr" "$root/"
cp -a "${GIT_OUTPUT:-/out}/legal/attribution/git" "$root/usr/share/doc/git/build-info"
cp "$recipe/debian/copyright" "$root/usr/share/doc/git/copyright"
cd "$recipe"
bash "$script_dir/changelog.sh" debian/changelog
gzip -n -9 -c debian/changelog >"$root/usr/share/doc/git/changelog.Debian.gz"

# Scan every real ELF file, including HTTP helpers; scripts and symlinks are skipped.
elfs=()
while IFS= read -r -d '' file; do
	if readelf -h "$file" >/dev/null 2>&1; then
		elfs+=("-e$file")
	fi
done < <(find "$root/usr" -type f -perm /111 -print0)
((${#elfs[@]} > 0))
dpkg-shlibdeps "${elfs[@]}"
dpkg-gencontrol -pgit -v"$package_version" -P"$root" -DArchitecture="$architecture"
chmod -R go-w "$root"
chmod 0755 "$root/DEBIAN"
(
	cd "$root"
	find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums
)
find "$root" -print0 | xargs -0 touch -h -d "@${SOURCE_DATE_EPOCH}"
dpkg-deb --root-owner-group --build "$root" "$output/git_${VERSION}-${PACKAGE_REVISION}_${architecture}.deb"
