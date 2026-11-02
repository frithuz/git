#!/usr/bin/env bash
# Validate the .dsc's file list and digests before copying a source package to a release or APT.
set -euo pipefail
dsc=$(realpath "${1:?Pass a .dsc file}")
cd "$(dirname "$dsc")"
[[ $(sed -n 's/^Format: //p' "$dsc") == '3.0 (quilt)' ]]
[[ $(sed -n 's/^Source: //p' "$dsc") == git ]]
printf '%s\n' "${dsc##*/}"
entries=$(awk '
  /^Checksums-Sha256:/ { active=1; next }
  active && /^[^ ]/ { active=0 }
  active { print }
' "$dsc")
[[ -n $entries ]]
while read -r digest size file extra; do
	[[ $digest =~ ^[0-9a-f]{64}$ && $size =~ ^[0-9]+$ && -z ${extra:-} ]]
	[[ $file =~ ^git_[a-zA-Z0-9.+~_-]+\.(orig(-[a-zA-Z0-9-]+)?\.tar\.(xz|gz)|debian\.tar\.xz)$ ]]
	[[ -f $file && ! -L $file && $(stat -c %s "$file") == "$size" ]]
	printf '%s  %s\n' "$digest" "$file" | sha256sum --check --strict >/dev/null
	printf '%s\n' "$file"
done <<<"$entries"
