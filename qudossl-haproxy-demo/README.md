# QudoSSL HAProxy Migration Demo

A **self-contained, end-to-end demonstration** of migrating a real web service to
post-quantum TLS using **HAProxy + QudoSSL**. You start from a working baseline on
stock OpenSSL, then migrate HAProxy to QudoSSL and prove that the TLS handshake now
uses **ML-KEM hybrid key exchange** — with a single configuration line and a
HAProxy binary built against QudoSSL.

Everything you need is in this one directory. Follow this README top to bottom and
you will complete the whole migration without looking anywhere else.

> This demo is independent from the NGINX demo. It has its own Spring Boot app,
> its own Docker images, and its own scripts.

```
        ┌─────────┐   HTTPS / TLS 1.3     ┌───────────────────────┐   HTTP :8080   ┌──────────────────┐
 client │ browser │ ───────────────────▶  │ HAProxy  (TLS term.)  │ ─────────────▶ │  Spring Boot app │
        │  curl   │   ML-KEM key exch.     │ built against QudoSSL  │                │  (plain HTTP)    │
        └─────────┘                        └───────────────────────┘                └──────────────────┘
                          ▲  the migration happens here — HAProxy only
```

The Spring Boot application never speaks TLS. **HAProxy terminates TLS** and
forwards plain HTTP to the app on port 8080. That is exactly why the migration
touches only the proxy: the application is untouched.

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
| ~2 GB free disk, ~20 min for the first QudoSSL build | It compiles OpenSSL 3.5.7 + HAProxy from source; it caches afterwards |
| `openssl` on your machine | Only to generate the local test certificate |
| Outbound HTTPS to github.com and haproxy.org | To download the QudoSSL source release and HAProxy |

No QudoSSL binaries are committed here. The QudoSSL HAProxy image **downloads the
public QudoSSL Commercial 1.0.0 source release, verifies its signature, and builds
it** — see [`haproxy/Dockerfile.qudossl`](haproxy/Dockerfile.qudossl).

---

## What's in this directory

```
qudossl-haproxy-demo/
├── README.md                        ← you are here
├── pom.xml                          Spring Boot app build
├── src/…                            the app (Java, HTTP only on :8080)
├── Dockerfile                       builds the app image
├── docker-compose.yml               BEFORE: baseline on stock OpenSSL
├── docker-compose.qudossl.yml       AFTER:  QudoSSL, STANDARD build
├── docker-compose.qudossl-fips.yml  AFTER:  QudoSSL, FIPS build
├── haproxy/
│   ├── haproxy.cfg                  BEFORE config (classical)
│   ├── haproxy.qudossl.cfg          AFTER  config (+1 line: ML-KEM curves)
│   └── Dockerfile.qudossl           builds HAProxy against QudoSSL (std + FIPS)
├── certs/                           generated test cert lands here (git-ignored)
└── scripts/
    ├── generate-test-certificate.sh self-signed localhost cert (+ combined .pem)
    ├── verify-tls.sh                what did TLS negotiate? (informational)
    └── verify-qudossl.sh            strict PASS/FAIL post-quantum proof
```

---

## Part 1 — Baseline (BEFORE): prove it works on stock OpenSSL

**Step 1 — Generate the test certificate.**
```bash
./scripts/generate-test-certificate.sh
```
This produces `certs/server.crt`, `certs/server.key`, and — because HAProxy reads
cert+key from one file — `certs/server.pem`.

**Step 2 — Bring up the baseline stack.**
```bash
docker compose up -d --build
```
This runs the Spring Boot app plus the **official HAProxy image** (stock,
classical-only OpenSSL).

**Step 3 — Confirm the service works over TLS.**
```bash
curl -k https://localhost/          # HTML landing page
curl -k https://localhost/health    # {"status":"UP"}
curl -k https://localhost/info      # JSON incl. "tlsTermination":"HAProxy"
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

## Part 2 — Migrate HAProxy to QudoSSL (AFTER)

**Step 6 — Understand the HAProxy build.**
Open [`haproxy/Dockerfile.qudossl`](haproxy/Dockerfile.qudossl). Two things matter,
and both come straight from the QudoSSL migration handbook:
- HAProxy is compiled with `USE_OPENSSL=1 SSL_INC=/opt/qudossl/include
  SSL_LIB=/opt/qudossl/lib LDFLAGS="-Wl,-rpath,/opt/qudossl/lib"`. The
  **`-rpath` is mandatory** — it makes the binary find QudoSSL's libraries at
  runtime.
- The build **fails** unless `ldd` confirms HAProxy linked `/opt/qudossl/lib`
  (the link gate). You cannot accidentally ship a HAProxy that fell back to the
  distro OpenSSL.

**Step 7 — Understand the ONE config change.**
The migration adds exactly one functional line to the `global` section. Compare
the two configs:

```diff
--- haproxy/haproxy.cfg            (BEFORE)
+++ haproxy/haproxy.qudossl.cfg    (AFTER)
@@ global
     log stdout format raw local0 info
     maxconn 2048
+
+    # THE post-quantum line — ML-KEM hybrids first, classical curves as fallback
+    ssl-default-bind-curves X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1:secp384r1
```

The certificate, backend, timeouts, and headers are **unchanged**. `ssl-default-bind-curves`
applies the group list to every TLS `bind`. Group names are case-sensitive and
must match OpenSSL 3.5.7 exactly.

**Step 8 — Choose your build: standard or FIPS.**
This demo supports both. They use the **same HAProxy image**; only the OpenSSL
provider config the HAProxy process loads differs.

| Build | Compose file | Provider config | Use when |
|---|---|---|---|
| **Standard** | `docker-compose.qudossl.yml` | default provider | general post-quantum TLS |
| **FIPS** | `docker-compose.qudossl-fips.yml` | FIPS + base, `fips=yes` | FIPS 140-3 boundary required |

**Step 9 — Build and start the QudoSSL stack** (pick one; the first build
compiles OpenSSL + HAProxy and takes ~15–20 min, then caches):

```bash
# Standard build
docker compose -f docker-compose.qudossl.yml up -d --build

# …or FIPS build
docker compose -f docker-compose.qudossl-fips.yml up -d --build
```

**Step 10 — Confirm the app still serves (nothing changed for the app).**
```bash
curl -k https://localhost/health    # {"status":"UP"}
curl -k https://localhost/info      # still "tlsTermination":"HAProxy"
```

**Step 11 — Prove HAProxy is now linked to QudoSSL.**
```bash
docker exec haproxy-demo-proxy ldd /usr/local/sbin/haproxy | grep -E 'ssl|crypto'
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
  PASS  haproxy is linked against QudoSSL (/opt/qudossl/lib)
  PASS  standard (default) provider is active         # or: FIPS provider is active (FIPS + base)
  PASS  post-quantum group negotiated: X25519MLKEM768
  PASS  classical fallback works: a classical-only client negotiates secp256r1
===> RESULT: PASS  (4 checks)  — QudoSSL post-quantum TLS is active (standard build).
```

**That's the migration.** One HAProxy rebuild against QudoSSL, one config line,
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

### How do I see the negotiated group with HAProxy?

HAProxy exposes the key-exchange group via the `%[ssl_fc_curve]` sample fetch,
which this demo surfaces as the `X-TLS-Group` response header. It reflects the
group **this client** negotiated, and — unlike NGINX's `$ssl_curve`, which
prints a codepoint — HAProxy prints the readable **name**:

```
X-TLS-Group: SECP256R1          ← from a classical client (curl, most browsers)
X-TLS-Group: X25519MLKEM768     ← from a PQC-capable client
```

So `curl -skI https://localhost/` shows `SECP256R1` even though the server
offers ML-KEM first — that is post-quantum readiness with a safe classical
fallback (Supported ≠ Negotiated), not a misconfiguration. The authoritative
check remains `scripts/verify-qudossl.sh` (an in-container QudoSSL `s_client`
that offers the hybrid and prints `Negotiated TLS1.3 group: X25519MLKEM768`).

> Note the header **direction**: HAProxy's `http-request set-header` adds
> headers toward the **backend**; to surface TLS info to the **client** you must
> use `http-response set-header`, as this demo's config does.

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
| 2 | `curl` hangs then times out | The app isn't healthy yet. `docker compose logs app`; HAProxy waits for `app` to pass its healthcheck. |
| 3 | `503 Service Unavailable` | HAProxy is up but the backend is down. `docker compose logs app`; check it logged `Started DemoApplication`. |
| 4 | HAProxy container exits immediately, log says `cannot bind socket` for the cert | `certs/server.pem` is missing. Run `./scripts/generate-test-certificate.sh` (it creates the combined `.pem`). |
| 5 | QudoSSL image build fails downloading the QudoSSL tarball | No outbound HTTPS to github.com. Check connectivity; the URL is in `haproxy/Dockerfile.qudossl`. |
| 6 | Build fails downloading HAProxy (`haproxy-<ver>.tar.gz` 404) | That patch release moved. Rebuild with `--build-arg HAPROXY_VERSION=<current 3.0.x>` from haproxy.org. |
| 7 | Build ends with `FATAL: haproxy is not linked against QudoSSL` | The link gate did its job — the `-rpath`/`SSL_LIB` flags didn't take. Rebuild clean: `docker compose -f docker-compose.qudossl.yml build --no-cache haproxy`. |
| 8 | `FATAL: fipsmodule.cnf missing — install_fips failed` | The FIPS self-test/install step failed during build. Rebuild `--no-cache`; ensure the build host isn't out of memory. |
| 9 | `verify-qudossl.sh` → "proxy container is not running" | Start the QudoSSL stack first (`docker compose -f docker-compose.qudossl.yml up -d --build`). |
| 10 | `verify-qudossl.sh` → "baseline (stock) proxy — it has no QudoSSL" | You're running `docker-compose.yml` (baseline). Bring it down and start a `qudossl` compose file. |
| 11 | Check 3 fails: got `''` (no group) | Handshake failed inside the container. `docker exec haproxy-demo-proxy qudossl s_client -connect 127.0.0.1:443 -groups X25519MLKEM768` and read the error; usually a cert path or config typo. |
| 12 | `verify-qudossl.sh --fips` says "expected fips … but running standard" | You started the standard compose. Use `docker-compose.qudossl-fips.yml`, or drop `--fips`. |

Reset everything:
```bash
docker compose down; docker compose -f docker-compose.qudossl.yml down
docker compose -f docker-compose.qudossl-fips.yml down
docker image rm qudossl-haproxy-demo-proxy:1.0.0 qudossl-haproxy-demo-app:1.0.0 2>/dev/null || true
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
  installation and `deploy-haproxy` handbooks (proper certificates from your CA,
  systemd units, and your organisation's key management).
