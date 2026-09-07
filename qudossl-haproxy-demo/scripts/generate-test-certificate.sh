#!/usr/bin/env bash
# generate-test-certificate.sh — self-signed TLS certificate for THIS DEMO ONLY.
#
#   ┌───────────────────────────────────────────────────────────────────────┐
#   │  This certificate is intended only for demonstration/testing and must  │
#   │  NOT be used in production. It is self-signed, its private key is       │
#   │  unencrypted, and it is never committed to source control.             │
#   └───────────────────────────────────────────────────────────────────────┘
#
# The certificate is deliberately CLASSICAL (RSA-2048). Post-quantum security in
# this demo comes from the ML-KEM KEY EXCHANGE, not the certificate signature —
# the key exchange is what defends against "harvest now, decrypt later". Server
# certificates stay classical until PQC signature algorithms (e.g. ML-DSA) are
# broadly trusted, which the migration handbook covers separately.
#
# Output (HAProxy needs cert+key in ONE PEM file for its `crt` directive):
#   certs/server.crt   certificate
#   certs/server.key   private key
#   certs/server.pem   cert + key concatenated  ← used by HAProxy
#   (CN=localhost, SAN localhost + 127.0.0.1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/certs"
CRT="${CERT_DIR}/server.crt"
KEY="${CERT_DIR}/server.key"
PEM="${CERT_DIR}/server.pem"
DAYS=825

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: 'openssl' is required on your machine to generate the test certificate." >&2
  echo "       Install it (macOS: 'brew install openssl'; Debian/Ubuntu: 'apt-get install openssl')." >&2
  exit 1
fi

mkdir -p "${CERT_DIR}"

if [[ -f "${PEM}" && "${1:-}" != "--force" ]]; then
  echo "Test certificate already exists: ${PEM}"
  echo "Re-run with --force to regenerate."
  exit 0
fi

# Portable SAN handling: a throwaway config works across OpenSSL and LibreSSL.
CONF="$(mktemp)"
trap 'rm -f "${CONF}"' EXIT
cat > "${CONF}" <<'CNF'
[req]
distinguished_name = dn
x509_extensions    = v3_ext
prompt             = no

[dn]
C  = US
O  = QudoSSL Migration Demo (TEST ONLY)
CN = localhost

[v3_ext]
basicConstraints     = critical, CA:false
keyUsage             = critical, digitalSignature, keyEncipherment
extendedKeyUsage     = serverAuth
subjectAltName       = @san

[san]
DNS.1 = localhost
IP.1  = 127.0.0.1
CNF

echo "Generating a self-signed RSA-2048 test certificate (valid ${DAYS} days)..."
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${KEY}" -out "${CRT}" \
  -days "${DAYS}" -config "${CONF}" -extensions v3_ext >/dev/null 2>&1

# HAProxy's `crt` directive reads certificate + key from a single PEM file.
cat "${CRT}" "${KEY}" > "${PEM}"

chmod 600 "${KEY}"
chmod 644 "${CRT}"
chmod 644 "${PEM}"   # world-readable so the in-container haproxy user can read it (TEST key only)

echo
echo "Created:"
echo "  ${CRT}"
echo "  ${KEY}"
echo "  ${PEM}   (cert + key — HAProxy reads this)"
echo
echo "Subject / SAN:"
openssl x509 -in "${CRT}" -noout -subject -ext subjectAltName 2>/dev/null \
  | sed 's/^/  /'
echo
echo "REMINDER: demonstration/testing only — do not use in production."
