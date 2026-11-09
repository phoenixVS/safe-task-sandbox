# Throwaway image for running an untrusted repo. Debian/Ubuntu based images only (uses apt).
# Swap the language runtime with: BASE_IMAGE=python:3.12-slim-bookworm in sandbox.env
ARG BASE_IMAGE=node:22-bookworm-slim
FROM ${BASE_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates procps bash \
 && rm -rf /var/lib/apt/lists/*

# Never run package install hooks (preinstall/postinstall) unless you re-enable them yourself.
# Harmless on non-Node images.
ENV NPM_CONFIG_IGNORE_SCRIPTS=true \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NEXT_TELEMETRY_DISABLED=1 \
    DO_NOT_TRACK=1 \
    HOME=/home/sandbox

COPY --chmod=755 scripts/ /opt/sandbox/

# One non-root user (uid 1000) on every base image. The Node image already ships "node" as uid 1000: replace it.
RUN if id -u 1000 >/dev/null 2>&1; then userdel -r "$(id -nu 1000)" 2>/dev/null || true; fi \
 && useradd -m -u 1000 -s /bin/bash sandbox \
 && mkdir -p /work && chown sandbox:sandbox /work
USER sandbox
WORKDIR /work
