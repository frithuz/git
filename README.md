# Git builds

One focused build recipe for Git on Debian 13 (Trixie), producing:

- `amd64` and `arm64` Debian packages, both named `git`.
- A scratch OCI artifact with the same installed binaries under `/out/`.
- A Debian `3.0 (quilt)` source package matching the binaries, including embedded sources.
- One signed APT repository containing both architecture packages.

The source pins, toolchain images, package revision, and build timestamp are in
[`git.Dockerfile`](git.Dockerfile). [`scripts/build/git.sh`](scripts/build/git.sh)
holds the shared compiler options. The Debian and OCI outputs share one
compilation per architecture and consume the same installation tree. CI
separately rebuilds the extracted source package to verify it.

## Build locally

Requires Docker with Buildx. [Task](https://taskfile.dev/) is optional; the Docker
commands work directly. The builder needs outbound access to Debian, kernel.org,
GitHub, and the Ubuntu keyserver. No DHI login is required.

```sh
task build
# Equivalent:
docker buildx bake

# Faster development build for the current machine:
task build:native
```

The default builds both Linux architectures. Your builder must support both,
through native nodes or emulation. CI uses native runners for each architecture.

Outputs are ignored by Git:

```text
dist/
  deb/linux_amd64/git_2.56.0-1frithuz1_amd64.deb
  deb/linux_arm64/git_2.56.0-1frithuz1_arm64.deb
  git.oci.tar
  sources/linux_amd64/git_2.56.0-1frithuz1.dsc
  sources/linux_amd64/git_2.56.0-1frithuz1.debian.tar.xz
  sources/linux_amd64/git_2.56.0.orig.tar.xz
  sources/linux_amd64/git_2.56.0.orig-zlib-ng.tar.gz
  sources/linux_arm64/... (the same source-package files)
  repository-test/...
```

Exports keep platform subdirectories even for native builds. Both platforms
produce the same architecture-independent source package. The `.dsc` records the
matching package version and cryptographic hashes of all source archives. Git's
and zlib-ng's original archives retain their exact downloaded bytes. Rust's
standard library is supplied by the pinned compiler; its copyright and license
notices are retained under `debian/upstream/rust/`, without its source archive.
The Debian archive contains build instructions, source provenance, Git's original
signature and maintainer public key, and the shared compilation and packaging
scripts. Releases publish all four files together.

Select individual outputs with `docker buildx bake deb`, `image`, or `sources`.
Load the scratch image into Docker instead of exporting an OCI archive with:

```sh
task build:native -- image --set 'image.output=type=docker'
```

Use `task check` for local shell, Dockerfile, workflow, metadata, and Bake checks
(requires shellcheck, hadolint, actionlint, Python 3, curl, jq, and OpenSSL).
Checks include a local HTTPS test of OpenBao authentication and secret handling;
no production credentials are needed. CI additionally checks shfmt.
`task test` runs both container verification targets. Default builds already run
the relevant verification before exporting Debian packages or images.
After building both architectures, `task test:apt` additionally checks their
combined repository using an ephemeral signing key.
`task test:source` extracts the `.dsc` and rebuilds it as an unprivileged user
with network access disabled. To test just ARM64, use
`task test:source -- --set '*.platform=linux/arm64'`.

## Retrieve or rebuild the source

Enable `deb-src` in the APT configuration below, then download the version
corresponding to the installed binary:

```sh
apt source "git=$(dpkg-query -W -f '${Version}' git)"
```

Alternatively, download the `.dsc`, both `.orig` archives, and
`.debian.tar.xz` from the release into one directory and extract:

```sh
dpkg-source -x git_2.56.0-1frithuz1.dsc
```

The extracted `debian/rules` invokes the same compiler flags and packaging
scripts as the container build, using the extracted sources without downloads.
Use the pinned Rust image and listed build dependencies; see the extracted
`debian/README.source` for `dpkg-buildpackage` instructions. The toolchain's Rust
version must match `debian/build.env`. The existing toolchain supplies the
compiled standard library; rebuilding Git does not require `rust-src`.

The installed `/usr/share/doc/git/build-info/SOURCE-PACKAGE` (or the image's
`/out/legal/attribution/git/SOURCE-PACKAGE`) identifies the producing `.dsc` and
its SHA-256. The signed APT `Release` authenticates the `Sources` index and its archives;
the build-generated `.dsc` remains unsigned so both native jobs produce identical
files. Dynamically linked runtime libraries remain Debian's packages and use
Debian's source repositories. This replaces the earlier custom source bundle.

## Install on Trixie

```sh
sudo apt install ./dist/deb/linux_amd64/git_2.56.0-1frithuz1_amd64.deb
```

Use the matching `arm64` package on ARM machines. Package version
`1:2.56.0-1frithuz1` retains Debian Git's epoch so upgrades from the distribution
package sort correctly. This package replaces Debian's `git`; its reduced
feature set is intentional. There is no install-time compilation.

The shared build includes HTTPS/libcurl, PCRE2, OpenSSL hashing, static zlib-ng,
and `git subtree`. It omits Perl/Python integrations, GUI tools, translations,
server commands, manual pages, and shell completion, matching the original
devcontainer client build. Installing Debian add-ons such as `git-svn` does not
restore commands omitted at compile time.

Shared-library dependencies are generated with `dpkg-shlibdeps` against standard
Trixie packages. CA certificates are required; SSH and `less` are recommended.
Do not copy this build into Alpine or an older Debian release.

Notices, source provenance, and the recipe are installed under
`/usr/share/doc/git/build-info/` in the Debian package and
`/legal/attribution/git/` in the OCI tree.

## Use in Dockerfiles

```dockerfile
FROM ghcr.io/OWNER/git:2.56.0-1frithuz1@sha256:REPLACE_WITH_PUBLISHED_DIGEST AS git
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libcurl4t64 libpcre2-8-0 libssl3t64 openssh-client \
    && rm -rf /var/lib/apt/lists/*
COPY --from=git /out/ /
```

The scratch artifact is a file carrier; it has no runtime libraries, shell, or
entrypoint. Consumers supply its runtime dependencies. Use the Debian package
instead if you want APT to install and track those dependencies automatically.

Compared with the old artifact in `../devcontainer`, binaries now live under
`/usr/bin`, helpers under `/usr/lib/git-core`, and templates under
`/usr/share/git-core`; system configuration remains `/etc/gitconfig`. When
migrating that consumer, update its image reference, legal-component paths, and
any `/usr/local` Git assumptions. The `/out/` wrapper, `SOURCE` format, recipe
filename `git.Dockerfile`, and `build/ORIGIN` producer metadata are retained.
This repository does not modify or disable the sibling's existing publisher.

## Build the signed APT repository

After building both architectures, point the repository tool at a GnuPG home
containing your signing key. The directory must be accessible to the Linux
container; a dedicated signing home is preferable to a macOS keychain-backed one.
The source keyring is mounted read-only and copied to a temporary container
directory so GnuPG's locks and sockets work on macOS filesystem mounts.

```sh
export APT_GNUPGHOME=/absolute/path/to/signing-home
export APT_SIGNING_KEY=FULL_SIGNING_KEY_FINGERPRINT
task apt
```

This creates `dist/apt` with both binary packages, the complete source package,
architecture-specific `Packages` indexes, a shared `Sources` index,
`Release`, `InRelease`, `Release.gpg`, and `key.asc`. It refuses to overwrite an
existing output directory, mix package versions, omit either architecture, or
publish a `.dsc` whose digest differs from the source recorded by either binary.
For an encrypted key, set `APT_PASSPHRASE_FILE` to the absolute path of a file
containing its passphrase; interactive key entry is unavailable in `task apt`.

Host that directory on any HTTPS static host. Clients use one repository URL
and the same installation command on either architecture. For example, after
downloading `key.asc` and verifying its fingerprint against a trusted value:

```sh
sudo install -m 0644 key.asc /etc/apt/keyrings/frithuz-git.asc
sudo tee /etc/apt/sources.list.d/frithuz-git.sources >/dev/null <<'EOF'
Types: deb deb-src
URIs: https://apt.example.com/git/
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/frithuz-git.asc
EOF
sudo apt update
sudo apt install git
apt source "git=$(dpkg-query -W -f '${Version}' git)"
```

Replace the example URL with your actual host. APT selects the native package.
The generated repository is a snapshot of the supplied package pair; uploading
a new snapshot to your host replaces the previous one. Older packages and
source remain available as GitHub Release assets.

## CI and releases

Pull requests and pushes to `main` build both architectures without publishing.
Verification includes selected upstream Git tests (init, config, pack objects,
clone), zlib-ng's tests, Debian upgrade/removal, the scratch tree's functionality,
signed APT installation, matching source retrieval and extraction, rejection of
a modified repository index, and an offline source rebuild on each native runner.
`task test:source` runs the source rebuild check locally with the pinned toolchain.

Configure the GitHub repository before the first release:

1. Store a passphrase-free APT signing key in OpenBao and configure GitHub OIDC
   access as described below. Create an `apt` GitHub Actions environment and set
   its `SIGNING_KEY` variable to the full signing-key fingerprint. No APT private
   key or OpenBao token is stored in GitHub.
2. Configure your HTTPS host for the APT repository. After each release, download
   `apt-repository.tar.gz` from the release assets and extract its contents into
   the directory served at your repository URL. Hosting deployment is managed
   outside this workflow.
3. Ensure the repository can publish GHCR packages and GitHub Releases. The
   workflow uses `GITHUB_TOKEN`; no registry password is stored.
4. Publish the signing-key fingerprint through a trusted channel for clients.

To release, update pins as needed, increment `PACKAGE_REVISION` for every recipe,
library, or toolchain rebuild of the same Git release, and tag the commit:

```sh
bash scripts/metadata.sh
git tag v2.56.0-1frithuz1
git push origin v2.56.0-1frithuz1
```

The tag must match the Dockerfile's Git version and package revision. The workflow
tests both native builds, generates the signed repository, publishes the OCI
artifact to `ghcr.io/<owner>/<repository>`, attaches packages, source, public key,
checksums, and `apt-repository.tar.gz` to the release. The image receives
revision-specific and upstream-version tags; consumers should pin its digest.
This pipeline does not configure Quay.

### OpenBao signing-key setup

Releases authenticate to `https://vault.frithuz.dev` with a GitHub Actions OIDC
JWT, obtain a short-lived OpenBao token, and read the `private_key` field from
a KV v2 secret at `git/apt`. The release job uses the `apt` GitHub Actions
environment and reads its `SIGNING_KEY` variable as the public fingerprint used
to select the imported signing key. Only the release job has `id-token: write`;
pull requests and branch builds do not retrieve the key. The key is imported into a temporary
GnuPG home and removed after signing, including on failure. TLS verification
is required. The OpenBao endpoint must be reachable by GitHub-hosted runners.

Run the following setup with `gpg`, `gh`, and the `bao` CLI installed. Authenticate
`gh` to GitHub and `bao` to OpenBao using an administrator account. Replace
`OWNER/REPOSITORY` and the signing identity with your actual values.

```sh
export BAO_ADDR=https://vault.frithuz.dev
export APT_GITHUB_REPO=OWNER/REPOSITORY
export APT_GNUPGHOME="$HOME/.local/share/frithuz-git/gnupg"
mkdir -p "$APT_GNUPGHOME"
chmod 700 "$APT_GNUPGHOME"
gpg --homedir "$APT_GNUPGHOME" --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Frithuz Git APT <you@example.com>' ed25519 sign 2y
export APT_SIGNING_KEY
APT_SIGNING_KEY=$(gpg --homedir "$APT_GNUPGHOME" --batch --with-colons \
  --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
gh api --method PUT "repos/$APT_GITHUB_REPO/environments/apt" >/dev/null
gh variable set SIGNING_KEY --repo "$APT_GITHUB_REPO" --env apt --body "$APT_SIGNING_KEY"
```

Keep a secure backup of this dedicated keyring and its revocation certificate.
Renew the key before its two-year expiry and update the stored export afterward.
If you already have a dedicated passphrase-free key, reuse its GnuPG home and
fingerprint instead of generating another.

The examples use a KV v2 engine at `git/`, matching the repository name, and a
JWT auth mount at `jwt-github/`. Inspect existing mounts with `bao secrets list -detailed`
and `bao auth list`; run these enable commands only for mounts that do not exist:

```sh
bao secrets enable -path=git kv-v2
bao auth enable -path=jwt-github jwt
```

Store the key without creating an exported private-key file. `-cas=0` prevents
accidentally replacing an existing secret; omit it for an intentional update.

```sh
gpg --homedir "$APT_GNUPGHOME" --armor --export-secret-keys "$APT_SIGNING_KEY" |
  bao kv put -mount=git -cas=0 apt private_key=-

bao policy write git-apt-release - <<'EOF'
path "git/data/apt" {
  capabilities = ["read"]
}
EOF

# Skip this configuration if jwt-github/ already trusts GitHub Actions.
bao write auth/jwt-github/config \
  oidc_discovery_url=https://token.actions.githubusercontent.com \
  bound_issuer=https://token.actions.githubusercontent.com \
  jwt_supported_algs=RS256

repository_id=$(gh api "repos/$APT_GITHUB_REPO" --jq '.id | tostring')
jq -n --arg repository "$APT_GITHUB_REPO" --arg repository_id "$repository_id" '{
  role_type: "jwt",
  user_claim: "repository_id",
  bound_audiences: ["https://vault.frithuz.dev"],
  bound_claims_type: "glob",
  bound_claims: {
    repository: $repository,
    repository_id: $repository_id,
    ref: "refs/tags/v*",
    ref_type: "tag",
    event_name: "push",
    environment: "apt",
    workflow_ref: ($repository + "/.github/workflows/build.yml@refs/tags/v*")
  },
  token_policies: ["git-apt-release"],
  token_no_default_policy: true,
  token_type: "batch",
  token_ttl: "60s",
  token_explicit_max_ttl: "60s"
}' | bao write auth/jwt-github/role/git-release -
```

The policy permits reading only this secret. The JWT role requires the matching
repository name and immutable ID, a `v*` tag push, this workflow, the `apt`
environment, and the configured audience. Restrict who can create or update
release tags in GitHub. The public fingerprint is stored separately from the
private key as the `apt` environment's `SIGNING_KEY` variable.

An empty `SIGNING_KEY` variable is a placeholder and must be filled in before a
release. It contains the fingerprint, not the ASCII-armored private key.

These optional Actions variables, which can be set in the `apt` environment,
override the defaults:

| Variable | Default | Meaning |
| --- | --- | --- |
| `OPENBAO_ADDR` | `https://vault.frithuz.dev` | OpenBao HTTPS URL |
| `OPENBAO_AUTH_PATH` | `jwt-github` | JWT auth mount |
| `OPENBAO_ROLE` | `git-release` | JWT role |
| `OPENBAO_SECRET_PATH` | `git/data/apt` | KV v2 API path, including `data/` |
| `OPENBAO_AUDIENCE` | Value of `OPENBAO_ADDR`, without a trailing slash | OIDC audience |

When changing paths or audience, update the policy and JWT role accordingly.
GitHub's `APT_PRIVATE_KEY` and `APT_SIGNING_PASSPHRASE` secrets and the
`APT_SIGNING_KEY` Actions variable are no longer used.
Local `task apt` still uses `APT_GNUPGHOME` and `APT_SIGNING_KEY` directly.
See the [OpenBao JWT API](https://openbao.org/docs/api/auth/jwt/),
[KV v2 API](https://openbao.org/docs/api/secret/kv/kv-v2/), and
[GitHub OIDC reference](https://docs.github.com/en/actions/reference/security/oidc).

Update `VERSION` and `SHA256` together for Git, and all three `ZLIB_NG_*` pins
together for zlib-ng. `SOURCE_DATE_EPOCH` is a fixed build timestamp; update it
when moving to a new upstream release. Source archives are authenticated before
compilation. Debian dependencies are fetched from live Trixie repositories, so
base-image and source pins alone do not promise byte-for-byte reproducibility
across different build dates.

The build scripts were extracted from `frithuz/devcontainer` at commit
`82579883a0075a067416c9b50cf89d90b539c7ac`. Repository contributions use CC0-1.0;
Git and its embedded libraries retain the upstream licenses shipped in each artifact.
