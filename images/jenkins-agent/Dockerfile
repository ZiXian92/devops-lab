# syntax=docker/dockerfile:1

# Jenkins inbound agent for the lab: the official jenkins/inbound-agent (JDK 25, Debian
# trixie) plus kubectl, helm and podman. Runs as the base image's non-root `jenkins` user
# (uid 1000). See the jenkins-agent service in docker-compose.yaml.
#
# podman here is the remote client (podman-remote): it talks to the podman machine's API
# socket that docker-compose.yaml mounts in, so `podman build/run` and `docker build/run`
# (a symlink to podman) run on the machine, not inside this container.

ARG AGENT_VERSION=3391.va_37fa_a_305d6d-3-jdk25

# ---------------------------------------------------------------------------
# Stage 1: download and verify the tools (curl/tar never reach the final image)
# ---------------------------------------------------------------------------
FROM docker.io/library/debian:trixie-slim AS fetch

ARG TARGETARCH
ARG KUBECTL_VERSION=1.37.0
ARG HELM_VERSION=4.3.0
ARG PODMAN_VERSION=6.1.2

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Checksums come from the same release as the artifact: they catch a corrupt or truncated
# download, not a compromised release.
WORKDIR /dl
RUN set -eu; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    mkdir -p /out; \
    curl -fsSLO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"; \
    echo "$(curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${arch}/kubectl.sha256")  kubectl" | sha256sum -c -; \
    install -m 0755 kubectl /out/kubectl; \
    f="helm-v${HELM_VERSION}-linux-${arch}.tar.gz"; \
    curl -fsSLO "https://get.helm.sh/$f"; curl -fsSLO "https://get.helm.sh/$f.sha256sum"; \
    sha256sum -c "$f.sha256sum"; \
    tar -xzf "$f" --no-same-owner --strip-components=1 -C /out "linux-${arch}/helm"; \
    base="https://github.com/containers/podman/releases/download/v${PODMAN_VERSION}"; \
    f="podman-remote-static-linux_${arch}.tar.gz"; \
    curl -fsSLO "$base/$f"; curl -fsSLO "$base/shasums"; \
    grep " ${f}\$" shasums | sha256sum -c -; \
    tar -xzf "$f"; \
    install -m 0755 "bin/podman-remote-static-linux_${arch}" /out/podman

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM docker.io/jenkins/inbound-agent:${AGENT_VERSION}

USER root
COPY --from=fetch /out/ /usr/local/bin/
RUN ln -s podman /usr/local/bin/docker
COPY --chmod=0755 entrypoint.sh /usr/local/bin/lab-agent-entrypoint

USER jenkins
# The podman machine's API socket, mounted by docker-compose.yaml.
ENV CONTAINER_HOST=unix:///run/podman/podman.sock

ENTRYPOINT ["/usr/local/bin/lab-agent-entrypoint"]
