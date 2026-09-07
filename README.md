# QudoSSL Migration Demos

Two **completely independent**, customer-ready demonstrations of migrating a real
web service to **post-quantum TLS** with QudoSSL. Each demo takes you from a
working baseline on stock OpenSSL to a proxy that terminates TLS with **ML-KEM
hybrid key exchange** — and proves it.

| Demo | Reverse proxy | Directory | Start here |
|---|---|---|---|
| **NGINX** | NGINX built against QudoSSL | [`qudossl-nginx-demo/`](qudossl-nginx-demo/) | [its README](qudossl-nginx-demo/README.md) |
| **HAProxy** | HAProxy built against QudoSSL | [`qudossl-haproxy-demo/`](qudossl-haproxy-demo/) | [its README](qudossl-haproxy-demo/README.md) |

## These two demos are independent

They are **not** a shared backend behind two proxies. Each directory is a whole,
standalone project:

- its **own** Spring Boot application (different Java package, different content),
- its **own** Maven build, Dockerfile, and Docker Compose files,
- its **own** proxy config (before/after), certificates, and verification scripts,
- its **own** README that walks through the entire migration.

Pick one directory, `cd` into it, and follow **only** that README. You never need
to look at the other demo or at any file above the demo directory.

## What each demo shows

Both demos follow the same shape — the value is seeing it end to end for your proxy:

1. **Baseline (BEFORE):** `docker compose up -d --build`, then
   `curl -k https://localhost/` — a working service on stock OpenSSL, classical
   key exchange.
2. **Migrate (AFTER):** rebuild the proxy against QudoSSL (the Dockerfile does
   this from the **public QudoSSL Commercial 1.0.0 source release**, verifying its
   signature) and add **one** configuration line.
3. **Prove it:** `./scripts/verify-qudossl.sh` asserts the proxy is linked to
   QudoSSL, the expected provider is active, and the handshake actually negotiates
   `X25519MLKEM768` — while classical-only clients still fall back cleanly
   (**Supported ≠ Negotiated**).

Each demo supports **both a standard build and a FIPS build**, selected by which
compose file you run, and `verify-qudossl.sh` checks whichever one is live.

## The migration only touches the proxy

In both demos the Spring Boot app speaks **plain HTTP on port 8080** and never
terminates TLS. The proxy terminates TLS and forwards HTTP to the app. That is the
whole point: **post-quantum migration is a proxy change**, and the application is
untouched.

## Prerequisites (both demos)

- Docker + Docker Compose v2
- `openssl` on your machine (only to generate the local test certificate)
- Outbound HTTPS to github.com (QudoSSL source release) and to nginx.org /
  haproxy.org (the proxy source)
- ~2 GB disk and ~20 min for the first QudoSSL build (it compiles OpenSSL 3.5.7 +
  the proxy from source; it caches afterwards)

## ⚠️ Test material only

Each demo generates a **self-signed RSA certificate for `localhost`** for
**demonstration/testing only — never for production**. Certificates and private
keys are generated locally and are **not** committed. No QudoSSL binaries or
licenses are committed either; the images build QudoSSL from its signed public
source release.

## Not benchmarks, not a product

These are teaching/enablement demos that faithfully reuse the QudoSSL Commercial
migration handbook's provider names, library paths, group names, and build flags.
For a real deployment, follow the QudoSSL Commercial installation and
`deploy-nginx` / `deploy-haproxy` handbooks (CA-issued certificates, systemd
units, and your key-management practices).
