#!/usr/bin/env bash
# verify-tls.sh — show what the running proxy actually negotiates on :443.
#
# Informational (always exits 0 on a successful handshake). It reports the TLS
# protocol, cipher, and the negotiated KEY-EXCHANGE GROUP, so you can see the
# difference between the baseline (classical curve) and the QudoSSL stack
# (X25519MLKEM768). For a strict PASS/FAIL post-quantum assertion, use
# verify-qudossl.sh instead.
#
# Two paths, chosen automatically:
#   • QudoSSL stack  → runs a QudoSSL TLS client INSIDE the proxy container, the
#     only client that can offer ML-KEM groups and print their names.
#   • baseline stack → reads the proxy's own X-TLS-* response headers via curl
#     (a stock proxy has no in-container TLS client; the header is enough).
#
# Usage: ./scripts/verify-tls.sh

set -uo pipefail

PROXY="nginx-demo-proxy"
URL="https://localhost/"
GROUP_LIST="X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1:secp384r1"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${PROXY}"; then
  echo "Proxy container '${PROXY}' is not running. Bring a stack up first, e.g.:"
  echo "  docker compose up -d --build                              # baseline"
  echo "  docker compose -f docker-compose.qudossl.yml up -d --build # QudoSSL"
  exit 1
fi

if docker exec "${PROXY}" sh -c 'command -v qudossl' >/dev/null 2>&1; then
  # --- QudoSSL stack: authoritative in-container client --------------------
  bold "TLS verification against ${PROXY}:443  (QudoSSL client, in-container)"
  OUT="$(docker exec "${PROXY}" sh -c \
    "echo | qudossl s_client -connect 127.0.0.1:443 -groups '${GROUP_LIST}' -servername localhost 2>/dev/null")"
  if ! grep -q 'Protocol: TLS' <<<"${OUT}"; then
    echo "  Handshake FAILED inside the proxy container."; exit 1
  fi
  # s_client prints "Protocol: TLSv1.3", "New, TLSv1.3, Cipher is <name>", and
  # the group as "Negotiated TLS1.3 group: <name>" (ML-KEM) OR
  # "Peer Temp Key: ECDH, <curve>" (classical).
  PROTO="$(grep -m1 -E '^Protocol' <<<"${OUT}" | sed 's/.*: *//')"
  CIPHER="$(grep -m1 'Cipher is' <<<"${OUT}" | sed 's/.*Cipher is //')"
  GROUP="$(grep -m1 'Negotiated TLS1.3 group:' <<<"${OUT}" | sed 's/.*group: *//')"
  [[ -z "${GROUP}" ]] && GROUP="$(grep -m1 'Peer Temp Key: ECDH,' <<<"${OUT}" | sed -E 's/.*ECDH, *([^,]+),.*/\1/')"
  echo "  Protocol         : ${PROTO:-unknown}"
  echo "  Cipher           : ${CIPHER:-unknown}"
  echo "  Negotiated group : ${GROUP:-unknown}"
  echo
  if [[ "${GROUP}" == *MLKEM* ]]; then
    echo "  → Post-quantum key exchange is ACTIVE (${GROUP})."
  else
    echo "  → Classical group negotiated. If you expected PQC, check the config."
  fi
else
  # --- baseline stack: read the proxy's X-TLS-* headers via curl ------------
  bold "TLS verification against ${URL}  (baseline — reading X-TLS-* headers)"
  if ! command -v curl >/dev/null 2>&1; then
    echo "  curl is required for the baseline check."; exit 2
  fi
  HDRS="$(curl -skI "${URL}")"
  if [[ -z "${HDRS}" ]]; then echo "  Handshake FAILED — is the stack up?"; exit 1; fi
  PROTO="$(grep -i '^x-tls-protocol:' <<<"${HDRS}" | sed 's/.*: *//' | tr -d '\r')"
  CIPHER="$(grep -i '^x-tls-cipher:'   <<<"${HDRS}" | sed 's/.*: *//' | tr -d '\r')"
  GROUP="$(grep -i '^x-tls-group:'     <<<"${HDRS}" | sed 's/.*: *//' | tr -d '\r')"
  echo "  Protocol         : ${PROTO:-unknown}"
  echo "  Cipher           : ${CIPHER:-unknown}"
  echo "  Negotiated group : ${GROUP:-unknown}   (header value; classical curve name)"
  echo
  echo "  → This is the baseline on stock OpenSSL: classical key exchange, no ML-KEM."
  echo "    Migrate with docker-compose.qudossl.yml, then run verify-qudossl.sh."
fi
exit 0
