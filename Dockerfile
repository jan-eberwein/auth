# =============================================================================
# SNode.C Identity Provider — Multi-Stage Docker Build
#
# Strategy:
#   Stage 1 (builder):
#     - Clone jan-eberwein/snode.c (the fork with auth_idp integrated)
#     - Inject easyloggingpp (local supplement, not a git submodule)
#     - Replace src/apps/auth_idp and src/auth with this repo's source
#     - Build ONLY the auth_idp target using CMake + Ninja
#
#   Stage 2 (runtime):
#     - Debian slim image with binary + SNode.C shared libs
#     - Non-root user for security
#     - Persistent volumes for SQLite DB and RSA keys
# =============================================================================

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ninja-build \
    git \
    pkg-config \
    libssl-dev \
    libsqlite3-dev \
    libbrotli-dev \
    libmagic-dev \
    nlohmann-json3-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clone the SNode.C fork
ARG SNODEC_REPO=https://github.com/jan-eberwein/snode.c.git
ARG SNODEC_BRANCH=master
RUN git clone --depth=1 --branch ${SNODEC_BRANCH} ${SNODEC_REPO} snodec

# ── Fix: inject easyloggingpp (it's a local dir, not a git submodule) ─────────
# The snode.c repo's src/log/CMakeLists.txt uses find_package(EASYLOGGINGPP)
# which looks in ${EASYLOGGINGPP_ROOT} = supplement/easyloggingpp/
# We ship these two files in the auth repo so the Docker build is self-contained.
COPY supplement/easyloggingpp/ /build/snodec/supplement/easyloggingpp/

# ── Override with this repo's latest C++ source ───────────────────────────────
COPY src/apps/auth_idp/ /build/snodec/src/apps/auth_idp/
COPY src/auth/           /build/snodec/src/auth/

# ── Configure + Build (only auth_idp target) ──────────────────────────────────
# Note: CMakeLists is at src/ (not root), hence -S /build/snodec/src
RUN cmake \
    -B /build/snodec/build \
    -S /build/snodec/src \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSNODEC_SSO_MFA=ON \
    -DCMAKE_INSTALL_PREFIX=/opt/auth-idp \
    && cmake --build /build/snodec/build --target auth_idp --parallel $(nproc) \
    && cmake --install /build/snodec/build --component apps

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libsqlite3-0 \
    libbrotli1 \
    libmagic1 \
    ca-certificates \
    curl \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN useradd -r -s /sbin/nologin -d /app authidp

WORKDIR /app

# Binary from builder
COPY --from=builder /opt/auth-idp/bin/auth_idp ./auth_idp
RUN chmod +x ./auth_idp

# SNode.C shared libraries (logger, http, express, etc. are dynamic libs)
COPY --from=builder /opt/auth-idp/lib/ /usr/local/lib/
RUN ldconfig

# SQL schema files
COPY src/apps/auth_idp/database/ ./database/

# Startup script
COPY scripts/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

# Persistent data dirs
RUN mkdir -p /app/keys /app/data \
    && chown -R authidp:authidp /app

USER authidp

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://localhost:${IDP_PORT:-8080}/health | grep -q '"status"' || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/auth_idp"]
