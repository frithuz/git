#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources
# The slim base has no OpenSSL default CA-path symlinks until certificates are installed.
apt-get -o Acquire::https::CaInfo=/etc/ssl/certs/ca-certificates.crt -o APT::Update::Error-Mode=any update
apt-get -o Acquire::https::CaInfo=/etc/ssl/certs/ca-certificates.crt install -y --no-install-recommends \
	apt-utils dpkg-dev gnupg ca-certificates curl
rm -rf /var/lib/apt/lists/*
