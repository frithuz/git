#!/usr/bin/env bash
set -euo pipefail
mkdir -p dist/packages dist/sources-release dist/release
for architecture in amd64 arm64; do
	build="dist/builds/git-$architecture"
	[[ -s $build/git.oci.tar ]]
	found=0
	while IFS= read -r -d '' file; do
		[[ $(dpkg-deb -f "$file" Architecture) == "$architecture" ]]
		cp "$file" dist/packages/
		found=$((found + 1))
	done < <(find "$build/deb" -type f -name '*.deb' -print0)
	[[ $found == 1 ]]
	found=0
	while IFS= read -r -d '' dsc; do
		files=$(bash scripts/source-package-files.sh "$dsc")
		while IFS= read -r name; do
			file=$(dirname "$dsc")/$name
			if [[ -f dist/sources-release/$name ]]; then
				cmp "$file" "dist/sources-release/$name"
			else
				cp "$file" dist/sources-release/
				cp "$file" dist/release/
			fi
		done <<<"$files"
		found=$((found + 1))
	done < <(find "$build/sources" -type f -name '*.dsc' -print0)
	[[ $found == 1 ]]
done
