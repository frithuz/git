#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources
apt-get update
apt-get install -y --no-install-recommends \
	ca-certificates curl gcc make libc6-dev dpkg-dev gnupg xz-utils binutils \
	libcurl4-openssl-dev libpcre2-dev libssl-dev perl python3
rm -rf /var/lib/apt/lists/*
