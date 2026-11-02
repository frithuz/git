#!/usr/bin/env bash
# Debian's build entrypoint uses exactly the compiler and packaging scripts shipped by OCI.
set -euo pipefail
top=$(pwd)
# This file is generated from the producing build's pinned inputs, not maintained separately.
# shellcheck disable=SC1091
source debian/build.env
export VERSION SHA256 SIGNER ZLIB_NG_VERSION ZLIB_NG_COMMIT ZLIB_NG_SHA256
export PACKAGE_REVISION SOURCE_DATE_EPOCH
export GIT_OUTPUT=$top/debian/tmp
export ZLIB_NG_PREFIX=$top/debian/zlib-prefix
export PACKAGE_WORK_ROOT=$top/debian/package-root
export PACKAGE_OUTPUT
PACKAGE_OUTPUT=$(dirname "$top")
export PACKAGE_CONTROL_ROOT=$top

case ${1:?Pass clean, build, or binary} in
clean)
	rm -rf "$GIT_OUTPUT" "$ZLIB_NG_PREFIX" "$PACKAGE_WORK_ROOT"
	rm -f debian/build-stamp debian/files debian/substvars
	;;
build | binary)
	if [[ $(rustc --version) != "$RUSTC_VERSION" ]]; then
		echo "This source package records $RUSTC_VERSION; use the pinned Rust image in debian/recipe/git.Dockerfile" >&2
		exit 1
	fi
	if [[ ! -f debian/build-stamp ]]; then
		GIT_SOURCE_ROOT=$top bash "$top/debian/recipe/scripts/build/git.sh"
		legal=$GIT_OUTPUT/legal/attribution/git
		cp -a debian/recipe "$legal/build"
		cp debian/upstream/ORIGIN "$legal/build/ORIGIN"
		cp debian/upstream/VERSION "$legal/VERSION"
		printf 'architecture: %s\n' "$(dpkg --print-architecture)" >>"$legal/VERSION"
		dsc="$PACKAGE_OUTPUT/git_${VERSION}-${PACKAGE_REVISION}.dsc"
		{
			printf 'source-package: git\nversion: 1:%s-%s\ndsc: %s\n' "$VERSION" "$PACKAGE_REVISION" "${dsc##*/}"
			if [[ -f $dsc ]]; then
				printf 'sha256: %s\n' "$(sha256sum "$dsc" | cut -d' ' -f1)"
			fi
		} >"$legal/SOURCE-PACKAGE"
		touch debian/build-stamp
	fi
	if [[ $1 == binary ]]; then
		bash "$top/debian/recipe/scripts/build/package.sh"
	fi
	;;
*)
	echo "Unknown action: $1" >&2
	exit 1
	;;
esac
