# QudoSSL NGINX Migration Demo

A **self-contained, end-to-end demonstration** of migrating a real web service to
post-quantum TLS using **NGINX + QudoSSL**. You start from a working baseline on
stock OpenSSL, then migrate NGINX to QudoSSL and prove that the TLS handshake now
uses **ML-KEM hybrid key exchange** — with a single configuration line and an
NGINX binary built against QudoSSL.

Everything you need is in this one directory. Follow this README top to bottom and
you will complete the whole migration without looking anywhere else.

> This demo is independent from the HAProxy demo. It has its own Spring Boot app,
> its own Docker images, and its own scripts.

```
        ┌─────────┐   HTTPS / TLS 1.3     ┌───────────────────────┐   HTTP :8080   ┌──────────────────┐
 client │ browser │ ───────────────────▶  │  NGINX  (TLS term.)   │ ─────────────▶ │  Spring Boot app │
        │  curl   │   ML-KEM key exch.     │  built against QudoSSL │                │  (plain HTTP)    │
        └─────────┘                        └───────────────────────┘                └──────────────────┘
                          ▲  the migration happens here — NGINX only
```

The Spring Boot application never speaks TLS. **NGINX terminates TLS** and forwards
plain HTTP to the app on port 8080. That is exactly why the migration touches only
the proxy: the application is untouched.

---

## ⚠️ Test certificate notice

This demo generates a **self-signed RSA certificate for `localhost`**. It is
intended **only for demonstration/testing and must not be used in production**.
The private key is unencrypted and is never committed to source control.

The certificate is deliberately **classical (RSA)**. Post-quantum protection here
comes from the **key exchange** (ML-KEM), which is what defends against
"harvest now, decrypt later." Server certificates stay classical until PQC
signature algorithms (e.g. ML-DSA) are broadly trusted — a separate migration.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Docker + Docker Compose v2 | `docker compose version` should print v2.x |
| ~2 GB free disk, ~20 min for the first QudoSSL build | It compiles OpenSSL 3.5.7 + NGINX from source; it caches afterwards |
| `openssl` on your machine | Only to generate the local test certificate |
| Outbound HTTPS to github.com and nginx.org | To download the QudoSSL source release and NGINX |

No QudoSSL binaries are committed here. The QudoSSL NGINX image **downloads the
public QudoSSL Commercial 1.0.0 source release, verifies its signature, and builds
it** — see [`nginx/Dockerfile.qudossl`](nginx/Dockerfile.qudossl).

---

## What's in this directory

```
qudossl-nginx-demo/
├── README.md                        ← you are here
├── pom.xml                          Spring Boot app build
├── src/…                            the app (Java, HTTP only on :8080)
├── Dockerfile                       builds the app image
├── docker-compose.yml               BEFORE: baseline on stock OpenSSL
├── docker-compose.qudossl.yml       AFTER:  QudoSSL, STANDARD build
├── docker-compose.qudossl-fips.yml  AFTER:  QudoSSL, FIPS build
├── nginx/
│   ├── nginx.conf                   top-level config (identical before & after)
│   ├── conf.d/default.conf          BEFORE server block (classical)
│   ├── conf.d/qudossl.conf          AFTER  server block (+1 line: ML-KEM groups)
│   └── Dockerfile.qudossl           builds NGINX against QudoSSL (std + FIPS)
├── certs/                           generated test cert lands here (git-ignored)
└── scripts/
    ├── generate-test-certificate.sh self-signed localhost cert
    ├── verify-tls.sh                what did TLS negotiate? (informational)
    └── verify-qudossl.sh            strict PASS/FAIL post-quantum proof
```

---

## Part 1 — Baseline (BEFORE): prove it works on stock OpenSSL

**Step 1 — Generate the test certificate.**
```bash
./scripts/generate-test-certificate.sh
```

**Step 2 — Bring up the baseline stack.**
```bash
docker compose up -d --build
```
This runs the Spring Boot app plus the **official NGINX image** (stock,
classical-only OpenSSL).

**Step 3 — Confirm the service works over TLS.**
```bash
curl -k https://localhost/          # HTML landing page
curl -k https://localhost/health    # {"status":"UP"}
curl -k https://localhost/info      # JSON incl. "tlsTermination":"NGINX"
```
`-k` skips certificate validation (expected — it is a self-signed test cert).

**Step 4 — Observe the baseline key exchange (classical).**
```bash
./scripts/verify-tls.sh
```
You will see `TLSv1.3`, an AES-GCM cipher, and a **classical** group
(e.g. `x25519` / `prime256v1`). No ML-KEM. This is the "before" picture.

**Step 5 — Tear the baseline down.**
```bash
docker compose down
```

---

## Part 2 — Migrate NGINX to QudoSSL (AFTER)

**Step 6 — Understand the NGINX build.**
Open [`nginx/Dockerfile.qudossl`](nginx/Dockerfile.qudossl). Two things matter,
and both come straight from the QudoSSL migration handbook:
- NGINX is compiled with `--with-ld-opt="-L/opt/qudossl/lib -lssl -lcrypto
  -Wl,-rpath,/opt/qudossl/lib"`. The **`-rpath` is mandatory** — it makes the
  binary find QudoSSL's libraries at runtime.
- The build **fails** unless `ldd` confirms NGINX linked `/opt/qudossl/lib`
  (the link gate). You cannot accidentally ship an NGINX that fell back to the
  distro OpenSSL.

**Step 7 — Understand the ONE config change.**
The migration adds exactly one functional line. Compare the two server blocks:

```diff
--- nginx/conf.d/default.conf     (BEFORE)
+++ nginx/conf.d/qudossl.conf     (AFTER)
@@ server {
     ssl_protocols       TLSv1.2 TLSv1.3;
     ssl_ciphers         ECDHE-…-AES256-GCM-SHA384:…;
+
+    # THE post-quantum line — ML-KEM hybrids first, classical curves as fallback
+    ssl_conf_command Groups X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1:secp384r1;
```

The certificate, ciphers, backend, and headers are **unchanged**. Group names are
case-sensitive and must match OpenSSL 3.5.7 exactly.

**Step 8 — Choose your build: standard or FIPS.**
This demo supports both. They use the **same NGINX image**; only the OpenSSL
provider config the NGINX process loads differs.

| Build | Compose file | Provider config | Use when |
|---|---|---|---|
| **Standard** | `docker-compose.qudossl.yml` | default provider | general post-quantum TLS |
| **FIPS** | `docker-compose.qudossl-fips.yml` | FIPS + base, `fips=yes` | FIPS 140-3 boundary required |

**Step 9 — Build and start the QudoSSL stack** (pick one; the first build
compiles OpenSSL + NGINX and takes ~15–20 min, then caches):

```bash
# Standard build
docker compose -f docker-compose.qudossl.yml up -d --build

# …or FIPS build
docker compose -f docker-compose.qudossl-fips.yml up -d --build
```

**Step 10 — Confirm the app still serves (nothing changed for the app).**
```bash
curl -k https://localhost/health    # {"status":"UP"}
curl -k https://localhost/info      # still "tlsTermination":"NGINX"
```

**Step 11 — Prove NGINX is now linked to QudoSSL.**
```bash
docker exec nginx-demo-proxy ldd /usr/local/nginx/sbin/nginx | grep -E 'ssl|crypto'
# → libssl.so.3  => /opt/qudossl/lib/…    (NOT /usr/lib/x86_64-linux-gnu/…)
```

**Step 12 — Prove post-quantum key exchange is active.**
```bash
./scripts/verify-qudossl.sh            # auto-detects standard vs FIPS
# …or assert a specific build:
./scripts/verify-qudossl.sh --fips
```
Expected tail:
```
  PASS  nginx is linked against QudoSSL (/opt/qudossl/lib)
  PASS  standard (default) provider is active         # or: FIPS provider is active (FIPS + base)
  PASS  post-quantum group negotiated: X25519MLKEM768
  PASS  classical fallback works: a classical-only client negotiates secp256r1
===> RESULT: PASS  (4 checks)  — QudoSSL post-quantum TLS is active (standard build).
```

**That's the migration.** One NGINX rebuild against QudoSSL, one config line,
verified post-quantum key exchange — for both the standard and FIPS builds.

---

## Reading the result: Supported ≠ Negotiated

A common mistake is to confuse "the server **supports** ML-KEM" with "this
connection **used** ML-KEM." They are different, and `verify-qudossl.sh` checks
both directions:

- Offer the hybrid group list → the server **negotiates `X25519MLKEM768`** (the
  strongest group both sides share).
- Offer only a classical group → the server negotiates `secp256r1`.

The second case proves post-quantum is **negotiated, not forced**: existing
classical-only clients keep working while capable clients get post-quantum
protection. That is exactly what you want during a migration.

### Why does `curl` show `X-TLS-Group: prime256v1`, not ML-KEM?

The `X-TLS-Group` header reflects the group **this client** negotiated, and
`curl`/your browser is (today) a **classical** client — so it negotiates a
classical curve (`prime256v1`) even though the server offers ML-KEM first. That
is Supported ≠ Negotiated, live: the server is post-quantum-ready, the client
isn't yet, and the connection safely falls back. It is not a misconfiguration.

When a **PQC-capable** client connects (like the QudoSSL `s_client` the verify
scripts use), it negotiates `X25519MLKEM768`. NGINX's `$ssl_curve` then prints
the group's **IANA codepoint** rather than its name — `0x11ec` **is**
`X25519MLKEM768`. To see the readable name, use `scripts/verify-tls.sh` /
`verify-qudossl.sh`, which run that PQC client and print
`Negotiated TLS1.3 group: X25519MLKEM768`.

---

## Rollback

The baseline and QudoSSL stacks are separate compose files, so rollback is a
one-liner — bring down the QudoSSL stack and bring the baseline back up:

```bash
docker compose -f docker-compose.qudossl.yml down     # or the -fips file
docker compose up -d
./scripts/verify-tls.sh        # confirms classical key exchange is back
curl -k https://localhost/health
```

Nothing on the application side changes, because the app never terminated TLS.

---

## Troubleshooting

| # | Symptom | Cause / Fix |
|---|---|---|
| 1 | `curl: (7) Failed to connect to localhost port 443` | Stack isn't up, or another process holds 443. `docker compose ps`; free the port or stop the other service. |
| 2 | `curl` hangs then times out | The app isn't healthy yet. `docker compose logs app`; NGINX waits for `app` to pass its healthcheck. |
| 3 | `502 Bad Gateway` | NGINX is up but can't reach the app. Check `docker compose logs app` and that the app logs `Started DemoApplication`. |
| 4 | QudoSSL image build fails downloading the tarball | No outbound HTTPS to github.com, or a proxy/firewall. Check connectivity; the URL is in `nginx/Dockerfile.qudossl`. |
| 5 | Build fails at `gpg --verify` | Corrupted download or blocked key import. Re-run the build (`--no-cache`); the release key is fetched from the release assets. |
| 6 | Build ends with `FATAL: nginx is not linked against QudoSSL` | The link gate did its job — the `-rpath`/`-L` flags didn't take. Rebuild clean: `docker compose -f docker-compose.qudossl.yml build --no-cache nginx`. |
| 7 | `FATAL: fipsmodule.cnf missing — install_fips failed` | The FIPS self-test/install step failed during build. Rebuild `--no-cache`; ensure the build host isn't out of memory. |
| 8 | `verify-qudossl.sh` → "proxy container is not running" | Start the QudoSSL stack first (`docker compose -f docker-compose.qudossl.yml up -d --build`). |
| 9 | `verify-qudossl.sh` → "baseline (stock) proxy — it has no QudoSSL" | You're running `docker-compose.yml` (baseline). Bring it down and start a `qudossl` compose file. |
| 10 | Check 3 fails: got `''` (no group) | Handshake failed inside the container. `docker exec nginx-demo-proxy qudossl s_client -connect 127.0.0.1:443 -groups X25519MLKEM768` and read the error; usually a cert path or config typo. |
| 11 | `verify-qudossl.sh --fips` says "expected fips … but running standard" | You started the standard compose. Use `docker-compose.qudossl-fips.yml`, or drop `--fips`. |
| 12 | `X-TLS-Group`/access log shows `prime256v1` or `group=0x11ec`, not `X25519MLKEM768` | Expected — the header/log shows the *client's* negotiated group (classical `curl` → `prime256v1`; a PQC client → codepoint `0x11ec`). See "Why does `curl` show …" above; use the verify scripts for the name. |

Reset everything:
```bash
docker compose down; docker compose -f docker-compose.qudossl.yml down
docker compose -f docker-compose.qudossl-fips.yml down
docker image rm qudossl-nginx-demo-proxy:1.0.0 qudossl-nginx-demo-app:1.0.0 2>/dev/null || true
```

---

## Definition of Done (clean-room test)

On a machine that has never run this demo, a customer can:
1. `git clone` (or copy) this directory and `cd` into it — nothing else.
2. `./scripts/generate-test-certificate.sh`
3. `docker compose up -d --build` → `curl -k https://localhost/` works (baseline).
4. `docker compose down`
5. `docker compose -f docker-compose.qudossl.yml up -d --build`
6. `./scripts/verify-qudossl.sh` → **RESULT: PASS**, `X25519MLKEM768` negotiated.
7. Repeat 5–6 with `docker-compose.qudossl-fips.yml` + `verify-qudossl.sh --fips`.

No QudoSSL binaries, licenses, production certs, or private keys are committed.

---

## What this demo is / isn't

- **Is:** a faithful, runnable illustration of proxy-side PQC migration using the
  exact QudoSSL provider/library names, paths, groups, and build flags from the
  QudoSSL Commercial migration handbook.
- **Isn't:** a production deployment. Test cert, self-signed, `curl -k`, and a
  single-node compose. For real deployments, follow the QudoSSL Commercial
  installation and `deploy-nginx` handbooks (proper certificates from your CA,
  systemd units, and your organisation's key management).
