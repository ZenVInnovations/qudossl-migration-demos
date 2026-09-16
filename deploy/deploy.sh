#!/usr/bin/env bash
# Run both demos as hosted endpoints (see deploy/README.md).
#
#   EMAIL=you@example.com \
#   NGINX_HOST=demo-nginx.example.com HAPROXY_HOST=demo-haproxy.example.com \
#   ./deploy/deploy.sh
#
# nginx runs the FIPS build, HAProxy the standard build. Each proxy binds 443 inside
# its container; the overrides publish them on host loopback ports, so a front proxy
# must pass TLS through by SNI at TCP level — never terminate TLS in front, or the
# client is testing that proxy instead of QudoSSL.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

: "${EMAIL:?set EMAIL=... (certbot registration address)}"
: "${NGINX_HOST:?set NGINX_HOST=... (DNS name for the nginx demo)}"
: "${HAPROXY_HOST:?set HAPROXY_HOST=... (DNS name for the HAProxy demo)}"
WEBROOT=${WEBROOT:-/var/www/html}
export NGINX_DEMO_PORT=${NGINX_DEMO_PORT:-8444}
export HAPROXY_DEMO_PORT=${HAPROXY_DEMO_PORT:-8445}

say() { printf '\n== %s\n' "$1"; }

say "0/4 preflight"
command -v docker >/dev/null || { echo "docker is not installed"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "docker compose v2 is required"; exit 1; }
for h in "$NGINX_HOST" "$HAPROXY_HOST"; do
  getent hosts "$h" >/dev/null || { echo "DNS does not resolve yet: $h"; exit 1; }
done
echo "ok: docker, compose, DNS for both names"

say "1/4 certificates (HTTP-01, so port 80 must reach this host)"
sudo certbot certonly --webroot -w "$WEBROOT" \
  -d "$NGINX_HOST" -d "$HAPROXY_HOST" \
  --non-interactive --agree-tos -m "$EMAIL" --keep-until-expiring

sudo tee /etc/letsencrypt/renewal-hooks/deploy/qudossl-demos.sh >/dev/null <<HOOK
#!/bin/sh
# Writes the certificate file names each proxy config already expects, then restarts them.
set -eu
LE=/etc/letsencrypt/live/$NGINX_HOST
mkdir -p "$ROOT/qudossl-nginx-demo/certs" "$ROOT/qudossl-haproxy-demo/certs"
install -m 644 "\$LE/fullchain.pem" "$ROOT/qudossl-nginx-demo/certs/server.crt"
install -m 600 "\$LE/privkey.pem"   "$ROOT/qudossl-nginx-demo/certs/server.key"
cat "\$LE/fullchain.pem" "\$LE/privkey.pem" > "$ROOT/qudossl-haproxy-demo/certs/server.pem"
chmod 600 "$ROOT/qudossl-haproxy-demo/certs/server.pem"
docker restart nginx-demo-proxy haproxy-demo-proxy 2>/dev/null || true
HOOK
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/qudossl-demos.sh
sudo /etc/letsencrypt/renewal-hooks/deploy/qudossl-demos.sh

say "2/4 nginx demo — FIPS build, published on 127.0.0.1:$NGINX_DEMO_PORT"
(cd qudossl-nginx-demo &&
 docker compose -f docker-compose.qudossl-fips.yml -f ../deploy/nginx-fips.override.yml up -d --build)

say "3/4 HAProxy demo — standard build, published on 127.0.0.1:$HAPROXY_DEMO_PORT"
(cd qudossl-haproxy-demo &&
 docker compose -f docker-compose.qudossl.yml -f ../deploy/haproxy-standard.override.yml up -d --build)

say "4/4 verify (each demo's own PASS/FAIL proof)"
./qudossl-nginx-demo/scripts/verify-qudossl.sh --fips
./qudossl-haproxy-demo/scripts/verify-qudossl.sh --standard

cat <<EOF

Both demos are up on 127.0.0.1:$NGINX_DEMO_PORT (nginx, FIPS) and
127.0.0.1:$HAPROXY_DEMO_PORT (HAProxy, standard).

They are not reachable from outside until your front proxy passes these hostnames
through by SNI. Then verify from a CLIENT machine, not from this host:

  openssl s_client -connect $NGINX_HOST:443 -groups X25519MLKEM768 -tls1_3 -brief </dev/null
  openssl s_client -connect $HAPROXY_HOST:443 -groups X25519MLKEM768 -tls1_3 -brief </dev/null
EOF
