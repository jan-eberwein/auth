# SNode.C Identity Provider (C++)

**Live:** https://auth.janeberwein.at

OAuth2 Authorization Code Flow + PKCE + TOTP MFA + JWT RS256 — implemented entirely in **C++** using the [SNode.C](https://github.com/SNodeC/snode.c) framework. VPS deployment via Docker.

This is the Identity Provider component of the Master Thesis *"SSO & MFA with SNode.C"* by Jan Nicolas Eberwein (FH OÖ, 2025/2026).

## Features

| Feature | RFC / Standard |
|---|---|
| OAuth2 Authorization Code Flow + PKCE | RFC 6749 + RFC 7636 (S256 only) |
| TOTP Multi-Factor Authentication | RFC 6238 |
| JWT access tokens (RS256 + JWKS) | RFC 7519, RFC 7517 |
| PBKDF2-HMAC-SHA256 password hashing | NIST SP 800-132 |
| AES-256-GCM TOTP secret encryption | NIST SP 800-38D |
| Rate limiting (login + MFA) | OWASP guidelines |
| Federated login (Google, Apple, Meta) | OpenID Connect |
| Password reset flow | — |
| SQLite backend | — |
| First-run admin setup with claim token | — |
| OpenID Connect Discovery | OpenID Core §4 |
| JWKS endpoint | RFC 7517 |

## Architecture

```
auth.janeberwein.at (HTTPS)
        │
        ▼ Caddy reverse proxy (TLS termination)
        │
        ▼ 127.0.0.1:8080
        │
        ▼ Docker container
        │
        ▼ C++ auth_idp binary (SNode.C)
        │
        ├── SQLite DB (/app/data/auth.db)
        └── RSA keys  (/app/keys/)
```

## Build & Deploy (VPS)

### Prerequisites
- Docker 20+ with Compose v2
- DNS: `auth.janeberwein.at` → VPS IP
- Caddy (or nginx) configured as reverse proxy

### Quick Deploy

```bash
# 1. Clone this repo on the VPS
git clone https://github.com/jan-eberwein/auth.git /opt/apps/auth
cd /opt/apps/auth

# 2. Configure
cp .env.example .env
# Edit .env — set SETUP_CLAIM_TOKEN for first-run admin setup

# 3. Build the C++ binary (takes ~5-10 min on first build, cached after)
docker compose build

# 4. Start
docker compose up -d

# 5. Check logs
docker compose logs -f
```

### First Run
After starting, navigate to `https://auth.janeberwein.at/setup` and enter your `SETUP_CLAIM_TOKEN` to create the initial admin account.

### Update
```bash
cd /opt/apps/auth
git pull
docker compose build --no-cache   # rebuild with latest source
docker compose up -d --force-recreate
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `IDP_PORT` | `8080` | Internal HTTP port |
| `IDP_BASE_URL` | `http://localhost:8080` | Public HTTPS URL |
| `IDP_ISSUER` | same as BASE_URL | JWT `iss` claim |
| `IDP_PRIVATE_KEY_PATH` | `/app/keys/private_key.pem` | Auto-generated on first run |
| `IDP_PUBLIC_KEY_PATH` | `/app/keys/public_key.pem` | Auto-generated on first run |
| `DB_PATH` | `/app/data/auth.db` | SQLite database path |
| `TOTP_KEY_PATH` | *(empty)* | AES-256-GCM key for TOTP secrets |
| `IDP_ALLOWED_REDIRECT_URIS` | localhost variants | Comma-separated OAuth2 redirect URIs |
| `OAUTH_GOOGLE_CLIENT_ID` | *(empty)* | Google OAuth2 (optional) |
| `OAUTH_GOOGLE_CLIENT_SECRET` | *(empty)* | Google OAuth2 (optional) |
| `SMTP_COMMAND` | *(empty = browser display)* | Password reset email command |
| `SETUP_CLAIM_TOKEN` | *(empty)* | First-run admin bootstrap token |

## API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/auth/authorize` | GET | OAuth2 authorization endpoint |
| `/auth/token` | POST | Token exchange (code → JWT) |
| `/auth/userinfo` | GET | OIDC userinfo (Bearer token) |
| `/auth/login` | GET / POST | Login page + form handler |
| `/auth/mfa` | POST | TOTP verification |
| `/auth/register` | GET / POST | Registration |
| `/auth/enroll/totp` | POST | TOTP enrollment confirmation |
| `/auth/logout` | POST | Session logout |
| `/auth/forgot-password` | GET / POST | Password reset request |
| `/auth/reset-password` | GET / POST | Password reset form |
| `/auth/federated/:provider` | GET | Federated login (google/apple/meta) |
| `/dashboard` | GET | User dashboard |
| `/settings` | GET / POST | Account settings |
| `/setup` | GET / POST | First-run admin setup |
| `/.well-known/jwks.json` | GET | JWKS public keys |
| `/.well-known/openid-configuration` | GET | OIDC discovery |
| `/health` | GET | Health check |

## Caddy Configuration

Already configured on the VPS:
```
auth.janeberwein.at {
    reverse_proxy 127.0.0.1:8080
}
```

## Build Details

The Docker build:
1. Clones [jan-eberwein/snode.c](https://github.com/jan-eberwein/snode.c) (the full SNode.C framework fork)
2. Replaces `src/apps/auth_idp/` and `src/auth/` with this repo's source
3. Compiles only the `auth_idp` target using CMake + Ninja
4. Creates a minimal Debian slim runtime image (~50MB)

**Compiler requirements:** GCC ≥ 12.2 or Clang ≥ 13.0, C++20

## License

MIT — Copyright © 2025/2026 Jan Nicolas Eberwein & Volker Chr. (SNode.C)
