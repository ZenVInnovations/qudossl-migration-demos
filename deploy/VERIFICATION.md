# Verifying a deployed demo

Checks for the two demos once they are running as hosted endpoints. Every command
below was run against these demos; the expected output is what they actually print.

Set these first:

```sh
NGINX_HOST=demo-nginx.example.com      # nginx demo    — FIPS build
HAPROXY_HOST=demo-haproxy.example.com  # HAProxy demo  — standard build
```

Use an **OpenSSL 3.5 or newer** client (`openssl version`). Older clients, including
LibreSSL as shipped on macOS, do not know the ML-KEM groups and will report a classical
group no matter what the server offers.

---

## A. From a client machine

Run these from a laptop, **not from the host itself** — checking from the host can
hairpin through local routing and report the wrong group.

### A1. Post-quantum key exchange

```sh
openssl s_client -connect "$NGINX_HOST:443" -groups X25519MLKEM768 -tls1_3 -brief </dev/null
```

Expect:

```
Protocol version: TLSv1.3
Ciphersuite: TLS_AES_256_GCM_SHA384
Signature type: rsa_pss_rsae_sha256
Verification: OK
Negotiated TLS1.3 group: X25519MLKEM768
```

`Negotiated TLS1.3 group` is the proof. `Signature type` shows an ordinary RSA or ECDSA
certificate: the key exchange is post-quantum, nothing was reissued. Repeat for
`$HAPROXY_HOST`.

### A2. Classical clients still work

```sh
openssl s_client -connect "$NGINX_HOST:443" -groups secp256r1 -tls1_3 -brief </dev/null
```

Expect a successful handshake reporting `Peer Temp Key: ECDH, prime256v1` (= secp256r1).
The server offers post-quantum, it does not force it — old clients keep working.

### A3. Which build is running, from outside

ChaCha20-Poly1305 is not FIPS-approved, so the FIPS build refuses it and the standard
build accepts it:

```sh
openssl s_client -connect "$NGINX_HOST:443"   -tls1_3 -ciphersuites TLS_CHACHA20_POLY1305_SHA256 -brief </dev/null
openssl s_client -connect "$HAPROXY_HOST:443" -tls1_3 -ciphersuites TLS_CHACHA20_POLY1305_SHA256 -brief </dev/null
```

| Host | Expected |
|---|---|
| `$NGINX_HOST` (FIPS) | handshake **fails**: `tls alert handshake failure ... SSL alert number 40` |
| `$HAPROXY_HOST` (standard) | handshake succeeds: `Ciphersuite: TLS_CHACHA20_POLY1305_SHA256` |

### A4. The application through the tunnel

```sh
curl -sS "https://$NGINX_HOST/" -o /dev/null -w 'status=%{http_code}\n'
curl -sS "https://$NGINX_HOST/health"
curl -sSI "https://$NGINX_HOST/" | grep -i '^x-tls'
```

Expect `status=200`, a healthy response, and headers like:

```
x-tls-protocol: TLSv1.3
x-tls-cipher: TLS_AES_256_GCM_SHA384
x-tls-group: prime256v1
```

**`x-tls-group` shows the client's group, not the server's offer.** `curl` is usually
classical, so `prime256v1` (nginx) or `SECP256R1` (HAProxy) here is correct and proves
nothing about post-quantum support. A1 is the check that matters.

### A5. In a browser

Open `https://$NGINX_HOST/`. In Chrome, DevTools → Security names the key exchange, and
a current Chrome, Edge or Firefox will show `X25519MLKEM768`. A corporate proxy in the
path may downgrade it to a classical group: that is a finding about the network, not
about the server.

---

## B. On the host

### B1. Each demo's own check

```sh
cd /srv/qudossl-migration-demos
./qudossl-nginx-demo/scripts/verify-qudossl.sh --fips
./qudossl-haproxy-demo/scripts/verify-qudossl.sh --standard
```

Expect `RESULT: PASS (4 checks)` from each: the proxy is linked against QudoSSL, the
expected provider is active, X25519MLKEM768 is negotiated, and classical fallback works.

### B2. It really is QudoSSL Commercial

```sh
for c in nginx-demo-proxy haproxy-demo-proxy; do
  echo "== $c"
  docker exec $c sh -c 'ldd $(command -v nginx || command -v haproxy) | grep -E "libssl|libcrypto"'
  docker exec $c /opt/qudossl/bin/openssl version
  docker exec $c /opt/qudossl/bin/qudossl version | head -1
  docker exec $c /opt/qudossl/bin/openssl list -providers | grep -E 'name:|version:'
  docker exec $c sh -c 'echo "QUDO symbols: $(grep -ac QUDO /opt/qudossl/lib/libcrypto.so.3)"'
done
```

| Check | Expected |
|---|---|
| `ldd` | `libssl.so.3 => /opt/qudossl/lib/libssl.so.3` (same for `libcrypto`) |
| `openssl version` | `OpenSSL 3.5.7 9 Jun 2026` — plain upstream, no vendor suffix |
| `qudossl version` | `QudoSSL 1.0.0` |
| providers, nginx demo | `OpenSSL Base Provider` 3.5.7 + `OpenSSL FIPS Provider` **3.5.4** |
| providers, HAProxy demo | `OpenSSL Default Provider` 3.5.7 |
| `QUDO symbols` | **0** |

Zero `QUDO` symbols is the Commercial pass condition: the libraries are unmodified
upstream OpenSSL. A non-zero count means something other than Commercial is installed.

The proxy images fetch the QudoSSL Commercial source release and verify its SHA-256 and
GPG signature during `docker build`, so a tampered tarball fails the build rather than
shipping.

---

## C. Sign-off

| # | Check | nginx (FIPS) | HAProxy (standard) |
|---|---|---|---|
| A1 | X25519MLKEM768 negotiated, `Verification: OK` | ☐ | ☐ |
| A2 | Classical client falls back to prime256v1 | ☐ | ☐ |
| A3 | ChaCha20 refused / accepted as expected | ☐ refused | ☐ accepted |
| A4 | App returns 200 through the tunnel | ☐ | ☐ |
| A5 | Browser shows the hybrid group | ☐ | ☐ |
| B1 | `verify-qudossl.sh` 4/4 PASS | ☐ | ☐ |
| B2 | Commercial identity table matches | ☐ | ☐ |
