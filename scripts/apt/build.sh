#!/usr/bin/env bash
# Build a signed repository from package artifacts. Requires Debian's apt-utils and GnuPG.
set -euo pipefail

input=$(realpath "${1:?usage: build.sh BINARY_INPUT SOURCE_INPUT OUTPUT}")
source_input=$(realpath "${2:?usage: build.sh BINARY_INPUT SOURCE_INPUT OUTPUT}")
output=$(realpath -m "${3:?usage: build.sh BINARY_INPUT SOURCE_INPUT OUTPUT}")
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
manifest_helper=${SOURCE_MANIFEST_HELPER:-$script_dir/../source-package-files.sh}
key=${APT_SIGNING_KEY:?Set APT_SIGNING_KEY to the signing key fingerprint}
architectures=${APT_ARCHITECTURES:-amd64 arm64}
if [[ -e $output ]]; then
	echo "Output already exists: $output (choose an empty destination)" >&2
	exit 1
fi
mkdir -p "$output/pool/main/g/git"
version=
declare -A seen=()
declare -A binary_source=()
while IFS= read -r -d '' file; do
	package=$(dpkg-deb -f "$file" Package)
	architecture=$(dpkg-deb -f "$file" Architecture)
	package_version=$(dpkg-deb -f "$file" Version)
	if [[ $package != git || " $architectures " != *" $architecture "* ||
		-n ${seen[$architecture]:-} || (-n $version && $version != "$package_version") ]]; then
		echo "Unexpected, duplicate, or mismatched package: $file" >&2
		exit 1
	fi
	version=$package_version
	if ! record=$(dpkg-deb --fsys-tarfile "$file" |
		tar -xOf - ./usr/share/doc/git/build-info/SOURCE-PACKAGE); then
		echo "Missing source-package provenance in $file" >&2
		exit 1
	fi
	binary_source[$architecture]=$(sed -n 's/^sha256: //p' <<<"$record")
	[[ ${binary_source[$architecture]} =~ ^[0-9a-f]{64}$ ]]
	[[ $(sed -n 's/^dsc: //p' <<<"$record") == "git_${version#*:}.dsc" ]]
	seen[$architecture]=1
	cp "$file" "$output/pool/main/g/git/"
done < <(find "$input" -type f -name '*.deb' -print0 | sort -z)

# One source package serves both architectures. Copies from native jobs must agree byte-for-byte.
source_count=0
while IFS= read -r -d '' dsc; do
	[[ $(sed -n 's/^Version: //p' "$dsc") == "$version" ]]
	[[ ${dsc##*/} == "git_${version#*:}.dsc" ]]
	files=$(bash "$manifest_helper" "$dsc")
	while IFS= read -r name; do
		file=$(dirname "$dsc")/$name
		destination=$output/pool/main/g/git/$name
		if [[ -e $destination ]]; then
			cmp "$file" "$destination"
		else
			cp "$file" "$destination"
		fi
	done <<<"$files"
	source_count=$((source_count + 1))
done < <(find "$source_input" -type f -name '*.dsc' -print0 | sort -z)
if [[ $source_count == 0 ]]; then
	echo 'Missing matching Debian source package' >&2
	exit 1
fi

cd "$output"
source_digest=$(sha256sum "pool/main/g/git/git_${version#*:}.dsc" | cut -d' ' -f1)
for architecture in $architectures; do
	if [[ -z ${seen[$architecture]:-} ]]; then
		echo "Missing Git package for $architecture" >&2
		exit 1
	fi
	if [[ ${binary_source[$architecture]} != "$source_digest" ]]; then
		echo "Source package does not match the source digest recorded by the $architecture binary" >&2
		exit 1
	fi
	index="dists/trixie/main/binary-$architecture"
	mkdir -p "$index"
	apt-ftparchive --arch "$architecture" packages pool/main/g/git >"$index/Packages"
	gzip -n -9 -c "$index/Packages" >"$index/Packages.gz"
done
mkdir -p dists/trixie/main/source
apt-ftparchive sources pool/main/g/git >dists/trixie/main/source/Sources
gzip -n -9 -c dists/trixie/main/source/Sources >dists/trixie/main/source/Sources.gz
apt-ftparchive \
	-o APT::FTPArchive::Release::Origin=Frithuz \
	-o APT::FTPArchive::Release::Label='Frithuz Git' \
	-o APT::FTPArchive::Release::Suite=trixie \
	-o APT::FTPArchive::Release::Codename=trixie \
	-o APT::FTPArchive::Release::Architectures="$architectures" \
	-o APT::FTPArchive::Release::Components=main \
	release dists/trixie >Release.tmp
mv Release.tmp dists/trixie/Release
gpg --batch --yes --armor --export "$key" >key.asc
[[ -s key.asc ]]
sign=(gpg --batch --yes --local-user "$key" --digest-algo SHA256)
if [[ -n ${APT_PASSPHRASE_FILE:-} ]]; then
	sign+=(--pinentry-mode loopback --passphrase-file "$APT_PASSPHRASE_FILE")
fi
"${sign[@]}" \
	--clearsign --output dists/trixie/InRelease dists/trixie/Release
"${sign[@]}" --armor \
	--detach-sign --output dists/trixie/Release.gpg dists/trixie/Release
gpg --batch --verify dists/trixie/InRelease
printf 'Git %s; architectures: %s\n' "$version" "$architectures" >index.html
# Repository contents are public, even when the signing process uses a private umask.
find "$output" -type d -exec chmod 0755 {} +
find "$output" -type f -exec chmod 0644 {} +
echo "Signed APT repository: $output"
