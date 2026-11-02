# syntax=docker/dockerfile:1
ARG VERSION=2.56.0
ARG SHA256=26c56c296b38c0695b26fa95f475f1d01704d2d38e73465ca30b0b2f5dc789d3
ARG PACKAGE_REVISION=1frithuz1
ARG SOURCE_DATE_EPOCH=1790553600
ARG SIGNER=96E07AF25771955980DAD10020D04E5A713660A7
ARG ZLIB_NG_VERSION=2.3.3
ARG ZLIB_NG_COMMIT=12731092979c6d07f42da27da673a9f6c7b13586
ARG ZLIB_NG_SHA256=a0d2a5d122c84b56a793a1553a9c3327fb2eb7469bf7a86b79e3c7be5d92e8d6

FROM rust:1.99-slim-trixie@sha256:1a939748a7cbab172de91a014e3804a97af1394a8c844faa67fce9401c4e40fb AS rust
FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS debian

FROM rust AS build
ARG VERSION
ARG SHA256
ARG SOURCE_DATE_EPOCH
ARG SIGNER
ARG ZLIB_NG_VERSION
ARG ZLIB_NG_COMMIT
ARG ZLIB_NG_SHA256
ARG TARGETARCH
RUN --mount=type=cache,id=apt-lists-$TARGETARCH,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=bind,source=scripts/build/run.sh,target=/mnt/src/scripts/build/run.sh \
    --mount=type=bind,source=scripts/build/dependencies.sh,target=/mnt/src/scripts/build/dependencies.sh \
    bash /mnt/src/scripts/build/run.sh /mnt/src/scripts/build/dependencies.sh
RUN --mount=type=bind,source=scripts/build/run.sh,target=/mnt/src/scripts/build/run.sh \
    --mount=type=bind,source=scripts/build/git.sh,target=/mnt/src/scripts/build/git.sh \
    bash /mnt/src/scripts/build/run.sh /mnt/src/scripts/build/git.sh

# Recipe changes invalidate assembly, without recompiling an unchanged Git build.
FROM build AS prepared
ARG REVISION=local
ARG REPOSITORY_URL=local
ARG PACKAGE_REVISION
COPY git.Dockerfile docker-bake.hcl LICENSE README.md Taskfile.yml .dockerignore /recipe/
COPY scripts/ /recipe/scripts/
COPY test/ /recipe/test/
COPY debian/ /recipe/debian/
RUN bash /recipe/scripts/build/artifact.sh

FROM prepared AS package
RUN bash /recipe/scripts/build/package.sh

# Both distributable formats depend on verification in a clean, standard Trixie image.
FROM debian AS verify
ARG VERSION
ARG ZLIB_NG_VERSION
COPY --from=rust /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=package /packages/ /packages/
COPY --from=prepared /out/ /artifact/
RUN --mount=type=bind,source=test/install.sh,target=/mnt/src/test/install.sh \
    --mount=type=bind,source=test/smoke.sh,target=/mnt/src/test/smoke.sh \
    bash /mnt/src/test/install.sh

FROM scratch AS artifact
ARG VERSION
ARG SHA256
ARG PACKAGE_REVISION
ARG REVISION=local
ARG REPOSITORY_URL=local
LABEL org.opencontainers.image.title="Git build artifact" \
    org.opencontainers.image.version="$VERSION-$PACKAGE_REVISION" \
    org.opencontainers.image.source=$REPOSITORY_URL \
    org.opencontainers.image.revision=$REVISION \
    dev.frithuz.git.source-sha256=$SHA256
COPY --from=verify /artifact/ /out/

FROM scratch AS deb
COPY --from=verify /packages/ /

FROM scratch AS sources
COPY --from=prepared /sources/ /

FROM build AS source-verify
COPY --from=prepared /sources/ /source-package/
RUN --network=none --mount=type=bind,source=test/source.sh,target=/mnt/src/test/source.sh \
    --mount=type=bind,source=test/smoke.sh,target=/mnt/src/test/smoke.sh \
    bash /mnt/src/test/source.sh

FROM scratch AS source-test
COPY --from=source-verify /source-verified /

FROM scratch AS test
COPY --from=verify /verified /

# This tooling image also builds the APT repository locally, without host Debian tools.
FROM debian AS repository-tools
COPY --from=rust /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
RUN --mount=type=bind,source=scripts/build/repository-tools.sh,target=/mnt/src/scripts/build/repository-tools.sh \
    bash /mnt/src/scripts/build/repository-tools.sh
COPY scripts/apt/build.sh /usr/local/lib/git-build/apt.sh
COPY scripts/apt/local-sign.sh /usr/local/lib/git-build/local-sign.sh
COPY scripts/source-package-files.sh /usr/local/lib/source-package-files.sh

FROM repository-tools AS repository-verify
ARG VERSION
ARG ZLIB_NG_VERSION
COPY --from=package /packages/ /input/
COPY --from=prepared /sources/ /source/
COPY test/smoke.sh test/apt.sh /tests/
RUN bash /tests/apt.sh

FROM scratch AS repository-test
COPY --from=repository-verify /verified /
