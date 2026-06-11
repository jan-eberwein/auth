# =============================================================================
# SNode.C Identity Provider — STANDALONE build on VANILLA upstream SNode.C
#
# Unlike the fork-based Dockerfile, this:
#   Stage 1a (snodec): clone + build + INSTALL upstream github.com/SNodeC/snode.c
#   Stage 1b (builder): build THIS repo standalone via find_package(snodec),
#                       with its own vendored db-sqlite + nayuki-qrcodegen
#   Stage 2  (runtime): Debian/Ubuntu slim with binary + snodec shared libs
#
# No fork of snode.c is required.
# =============================================================================

# ── Stage 1a: build + install vanilla upstream SNode.C ───────────────────────
FROM ubuntu:24.04 AS snodec
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git pkg-config \
    libssl-dev libsqlite3-dev libbrotli-dev libmagic-dev nlohmann-json3-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
ARG SNODEC_REPO=https://github.com/SNodeC/snode.c.git
ARG SNODEC_REF=master
RUN git clone --depth=1 --recurse-submodules --shallow-submodules \
        --branch ${SNODEC_REF} ${SNODEC_REPO} snodec

# Install the framework so downstream find_package(snodec) works.
RUN cmake -B /build/snodec/build -S /build/snodec -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/snodec \
    && cmake --build /build/snodec/build --parallel "$(nproc)" \
    && cmake --install /build/snodec/build

# ── Stage 1b: build the auth IdP standalone against the installed snodec ──────
FROM snodec AS builder
WORKDIR /app
COPY CMakeLists.txt ./
COPY src/ ./src/
RUN cmake -B build -S . -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH=/opt/snodec \
    && cmake --build build --parallel "$(nproc)" \
    && mkdir -p /opt/auth-idp/bin /opt/auth-idp/lib \
    && cp build/auth_idp /opt/auth-idp/bin/ \
    && find /opt/snodec -name "*.so*" -exec cp -dP {} /opt/auth-idp/lib/ \;

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS runtime
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 libsqlite3-0 libbrotli1 libmagic1 ca-certificates curl openssl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -r -s /sbin/nologin -d /app authidp
WORKDIR /app

COPY --from=builder /opt/auth-idp/bin/auth_idp ./auth_idp
RUN chmod +x ./auth_idp
COPY --from=builder /opt/auth-idp/lib/ /usr/local/lib/
RUN ldconfig

COPY src/apps/auth_idp/database/ ./database/
COPY scripts/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

RUN mkdir -p /app/keys /app/data && chown -R authidp:authidp /app
USER authidp
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://localhost:${IDP_PORT:-8080}/health | grep -q '"status"' || exit 1
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/auth_idp"]
