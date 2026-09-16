# Running the demos as hosted endpoints

The demo READMEs walk through a migration on your own machine. This folder runs the
same two demos as **long-lived endpoints** instead, so someone can open them in a
browser and see a real post-quantum handshake — nginx on the **FIPS** build, HAProxy
on the **standard** build.

Still demonstration material: a small Spring Boot app behind a proxy. Treat the host
accordingly.

## What you need first

1. **A DNS name per demo**, both pointing at the host.
2. **A way for those names to reach the containers on port 443.** Each proxy binds 443
   *inside* its container, and the overrides here publish them on host loopback ports
   (8444 and 8445 by default), so either:
   - a front proxy that passes TLS through at **TCP level by SNI** — nginx `stream`
     with `ssl_preread`, or HAProxy in `tcp` mode; or
   - a dedicated IP per demo, binding 443 directly (edit the overrides).

   **Do not terminate TLS in front of these demos.** If something else completes the
   handshake, the client is testing that proxy's TLS stack, not QudoSSL, and the demo
   proves nothing.
3. **certbot on the host.** The bundled certificates are self-signed for `localhost`,
   which gives a browser warning. A real certificate also makes the product's own
   point: post-quantum key exchange with an ordinary RSA or ECDSA certificate.

## Deploy

```sh
EMAIL=you@example.com \
NGINX_HOST=demo-nginx.example.com \
HAPROXY_HOST=demo-haproxy.example.com \
./deploy/deploy.sh
```

It refuses to start unless Docker, Compose v2 and both DNS names are in place, then
issues one certificate covering both names, installs a renewal hook that writes the
file names each proxy expects (`server.crt` + `server.key` for nginx, a combined
`server.pem` for HAProxy), builds and starts both demos, and finally runs each demo's
own `verify-qudossl.sh` — which exits non-zero if any check fails.

Override `WEBROOT`, `NGINX_DEMO_PORT` or `HAPROXY_DEMO_PORT` if the defaults don't fit.

## Verify from a client machine, not from the host

Checking from the host itself can hairpin through local routing and report the wrong
group.

```sh
openssl s_client -connect demo-nginx.example.com:443 \
  -groups X25519MLKEM768 -tls1_3 -brief </dev/null
```

Expect `Negotiated TLS1.3 group: X25519MLKEM768` and `Verification: OK`. In Chrome,
DevTools → Security names the key exchange. A corporate proxy in the path may downgrade
the handshake to a classical group — that is the network-path problem these demos exist
to expose, not a failure of the product.

## What is actually running

Both proxy images build **QudoSSL Commercial 1.0.0** from the public signed source
release, verifying the SHA-256 and the GPG signature at build time. Inside either proxy
container, `openssl version` reports plain `OpenSSL 3.5.7` and `libcrypto` carries zero
vendor symbols; `qudossl version` reports `QudoSSL 1.0.0`.
