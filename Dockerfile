# =============================================================================
# SNode.C Identity Provider — Multi-Stage Docker Build
#
# Strategy:
#   Stage 1 (builder):
#     - Clone jan-eberwein/snode.c (the fork with auth_idp integrated)
#     - Replace src/apps/auth_idp and src/auth with this repo's source
#     - Build ONLY the auth_idp target using CMake
#
#   Stage 2 (runtime):
#     - Debian slim image with only the binary + required shared libs
#     - Non-root user for security
#     - Persistent data volume for SQLite DB and keys
#
# Result: A minimal, production-ready C++ IdP container.
# =============================================================================

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Install all build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    build-essential \
    cmake \
    ninja-build \
    git \
    pkg-config \
    # C++ libraries required by SNode.C
    libssl-dev \
    libsqlite3-dev \
    libbrotli-dev \
    libmagic-dev \
    nlohmann-json3-dev \
    # Runtime deps (also needed at build time for some checks)
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clone the SNode.C fork (your fork, which has the auth_idp changes)
ARG SNODEC_REPO=https://github.com/jan-eberwein/snode.c.git
ARG SNODEC_BRANCH=master
RUN git clone --depth=1 --branch ${SNODEC_BRANCH} ${SNODEC_REPO} snodec \
    && cd snodec \
    && git submodule update --init --recursive --depth=1

# Copy this repo's C++ source over the cloned tree
# (Overrides src/apps/auth_idp and src/auth with the latest from this repo)
COPY src/apps/auth_idp/ /build/snodec/src/apps/auth_idp/
COPY src/auth/           /build/snodec/src/auth/

# Build — only the auth_idp target (saves ~90% build time vs full build)
RUN cmake \
    -B /build/snodec/build \
    -S /build/snodec \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSNODEC_SSO_MFA=ON \
    -DCMAKE_INSTALL_PREFIX=/opt/auth-idp \
    && cmake --build /build/snodec/build --target auth_idp --parallel $(nproc) \
    && cmake --install /build/snodec/build --component apps

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

ARG DEBIAN_FRONTEND=noninteractive

# Install only runtime dependencies (no compilers, no headers)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libsqlite3-0 \
    libbrotli1 \
    libmagic1 \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -r -s /sbin/nologin -d /app authidp

WORKDIR /app

# Copy the compiled binary from builder
COPY --from=builder /opt/auth-idp/bin/auth_idp ./auth_idp
RUN chmod +x ./auth_idp

# Copy database SQL files
COPY src/apps/auth_idp/database/ ./database/

# Copy startup script
COPY scripts/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

# Create persistent directories (keys and data — mount as volumes in production)
RUN mkdir -p /app/keys /app/data \
    && chown -R authidp:authidp /app

# Switch to non-root user
USER authidp

# Expose IdP port
EXPOSE 8080

# Health check using the /health endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://localhost:${IDP_PORT:-8080}/health | grep -q '"status"' || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/auth_idp"]
