# syntax=docker/dockerfile:1

# Local Helm CI/CD toolbox: lint, unit-test, validate, package and publish the charts in
# app-deployment-template-charts/ to the local Nexus OCI registry. Driven by `tasks`
# (tasks.sh); see the helm-cicd service in docker-compose.yaml.
#
# Base: Alpine Linux, current release at the time of writing (3.24.2). The final image adds
# nothing from apk -- only the four static binaries below and the task script -- and runs as
# an unprivileged user.

ARG ALPINE_VERSION=3.24.2

# ---------------------------------------------------------------------------
# Stage 1: download and verify the tools (wget/tar never reach the final image)
# ---------------------------------------------------------------------------
FROM docker.io/library/alpine:${ALPINE_VERSION} AS fetch

# Set automatically by the builder; falls back to the machine arch below.
ARG TARGETARCH
ARG HELM_VERSION=4.3.0
ARG HELM_UNITTEST_VERSION=1.1.2
ARG KUBECONFORM_VERSION=0.8.0

# Checksums come from the same release as the artifact: they catch a corrupt or truncated
# download, not a compromised release. Pin the hashes here if you need more than that.
RUN set -eu; \
    arch="${TARGETARCH:-$(uname -m)}"; \
    case "$arch" in \
      x86_64|amd64)  arch=amd64 ;; \
      aarch64|arm64) arch=arm64 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    echo "$arch" > /arch

WORKDIR /dl
RUN mkdir -p /out/bin /out/plugins/helm-unittest

# helm
RUN set -eu; arch=$(cat /arch); f="helm-v${HELM_VERSION}-linux-${arch}.tar.gz"; \
    wget -q "https://get.helm.sh/$f"; wget -q "https://get.helm.sh/$f.sha256sum"; \
    sha256sum -c "$f.sha256sum"; \
    tar -xzf "$f" --strip-components=1 -C /out/bin "linux-${arch}/helm"

# helm-unittest (plugin: plugin.yaml + binary, unpacked straight into the plugins dir)
RUN set -eu; arch=$(cat /arch); \
    base="https://github.com/helm-unittest/helm-unittest/releases/download/v${HELM_UNITTEST_VERSION}"; \
    f="helm-unittest-linux-${arch}-${HELM_UNITTEST_VERSION}.tgz"; \
    wget -q "$base/$f"; wget -q "$base/helm-unittest-checksum.sha"; \
    sum=$(grep "/${f}\$" helm-unittest-checksum.sha | cut -d' ' -f1); \
    [ -n "$sum" ]; echo "$sum  $f" | sha256sum -c; \
    tar -xzf "$f" -C /out/plugins/helm-unittest

# kubeconform
RUN set -eu; arch=$(cat /arch); \
    base="https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}"; \
    f="kubeconform-linux-${arch}.tar.gz"; \
    wget -q "$base/$f"; wget -q "$base/CHECKSUMS"; \
    grep " ${f}\$" CHECKSUMS | sha256sum -c; \
    tar -xzf "$f" -C /out/bin kubeconform

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM docker.io/library/alpine:${ALPINE_VERSION}

# Fixed numeric uid/gid so the container's user is stable and `runAsNonRoot`-style checks
# can verify it without resolving a name.
RUN addgroup -g 10001 helm \
 && adduser -D -u 10001 -G helm -h /home/helm -s /bin/sh helm

COPY --from=fetch /out/bin/ /usr/local/bin/
# Root-owned and read-only for the helm user: the toolbox cannot modify its own plugins.
COPY --from=fetch /out/plugins/ /opt/helm/plugins/
COPY --chmod=0755 tasks.sh /usr/local/bin/tasks

ENV HOME=/home/helm \
    HELM_PLUGINS=/opt/helm/plugins

USER 10001:10001
WORKDIR /workspace

CMD ["tasks", "help"]
