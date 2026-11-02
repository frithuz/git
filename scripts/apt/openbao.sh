#!/usr/bin/env bash
set -euo pipefail
# Never trace credentials, including when invoked with bash -x.
set +x
umask 077
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?GitHub Actions OIDC is required}"
: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?Grant id-token: write to the release job}"
: "${1:?Supply the private-key output filename}"
address=${OPENBAO_ADDR:-https://vault.frithuz.dev}
address=${address%/}
auth_path=${OPENBAO_AUTH_PATH:-jwt-github}
role=${OPENBAO_ROLE:-git-release}
secret_path=${OPENBAO_SECRET_PATH:-git/data/apt}
audience=${OPENBAO_AUDIENCE:-$address}
[[ $address == https://* && $ACTIONS_ID_TOKEN_REQUEST_URL == https://* ]]
[[ ! -e $1 ]]
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
http=(curl --disable --proto '=https' --fail --silent --show-error --connect-timeout 10 --max-time 60)

# Keep credentials out of command arguments, workflow outputs, and the environment.
printf 'Authorization: bearer %s\n' "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" >"$temporary/github-header"
"${http[@]}" --header "@$temporary/github-header" \
	--get --data-urlencode "audience=$audience" \
	"$ACTIONS_ID_TOKEN_REQUEST_URL" >"$temporary/oidc.json"
if ! jq -e --arg role "$role" \
	'{role: $role, jwt: (.value | select(type == "string" and length > 0))}' \
	"$temporary/oidc.json" >"$temporary/login.json"; then
	echo 'GitHub OIDC response did not contain a JWT' >&2
	exit 1
fi
"${http[@]}" --header 'Content-Type: application/json' --header 'X-Vault-Request: true' \
	--data-binary "@$temporary/login.json" \
	"$address/v1/auth/$auth_path/login" >"$temporary/token.json"
if ! token=$(jq -er '.auth.client_token | select(type == "string" and length > 0)' "$temporary/token.json"); then
	echo 'OpenBao login response did not contain a client token' >&2
	exit 1
fi
printf 'X-Vault-Token: %s\n' "$token" >"$temporary/bao-header"
unset token
"${http[@]}" --header "@$temporary/bao-header" --header 'X-Vault-Request: true' \
	"$address/v1/$secret_path" >"$temporary/secret.json"
if ! jq -er '.data.data.private_key | select(type == "string" and length > 0)' \
	"$temporary/secret.json" >"$temporary/private-key.asc"; then
	echo 'OpenBao KV v2 secret did not contain a private_key string' >&2
	exit 1
fi
mv "$temporary/private-key.asc" "$1"
