# syntax=docker/dockerfile:1

ARG GO_VERSION=1.27
ARG UBI_VERSION=9.8

# Cross-compile natively on the build platform; Go does not need emulation.
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS build

ARG TARGETOS
ARG TARGETARCH
# Version metadata is computed on the host by buildscripts/gen-ldflags.go,
# because .git is not part of the build context.
ARG LDFLAGS="-s -w"

WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -tags kqueue -ldflags "${LDFLAGS}" -o /out/mc .

# ubi-micro ships without a CA bundle; it is architecture independent,
# so take it from ubi-minimal on the build platform.
FROM --platform=$BUILDPLATFORM registry.access.redhat.com/ubi9/ubi-minimal:${UBI_VERSION} AS certs

FROM registry.access.redhat.com/ubi9/ubi-micro:${UBI_VERSION}

ARG VERSION
ARG REVISION

LABEL org.opencontainers.image.title="mc" \
    org.opencontainers.image.description="MinIO Client (fork of minio/mc)" \
    org.opencontainers.image.source="https://github.com/pixel365/minio-mc" \
    org.opencontainers.image.licenses="AGPL-3.0-only" \
    org.opencontainers.image.version="${VERSION}" \
    org.opencontainers.image.revision="${REVISION}"

# Upstream update endpoints (dl.min.io) are gone. mc only skips the check
# when both variables are off.
ENV MC_UPDATE=off \
    MINIO_UPDATE=off

COPY --from=certs /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/ca-trust/extracted/pem/
COPY --from=build /out/mc /usr/bin/mc
COPY CREDITS LICENSE /licenses/

ENTRYPOINT ["mc"]
