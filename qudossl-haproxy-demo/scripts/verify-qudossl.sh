#!/usr/bin/env bash
# verify-qudossl.sh — strict PASS/FAIL proof that QudoSSL post-quantum TLS is
# actually terminating traffic. Exits non-zero if any check fails.
#
# Works for BOTH the standard build and the FIPS build. It auto-detects which
# one is terminating TLS (from the proxy container's OPENSSL_CONF) and verifies
# the correct provider is active. Force an expectation with --standard / --fips.
#
# Checks:
#   1. haproxy is dynamically linked against QudoSSL (not the distro OpenSSL).
#   2. The expected provider is active (default  |  FIPS + base).
#   3. When offered the hybrid group list, the server NEGOTIATES X25519MLKEM768.
#   4. When offered ONLY a classical group, it negotiates that instead — proving
#      the PQC group is genuinely negotiated, not hard-forced (Supported≠Negotiated).
#
# Usage: ./scripts/verify-qudossl.sh [--standard|--fips]

set -uo pipefail

PROXY="haproxy-demo-proxy"
HAPROXY_BIN="/usr/local/sbin/haproxy"
HYBRID="X25519MLKEM768:SecP256r1MLKEM768:SecP384r1MLKEM1024:secp256r1:secp384r1"
EXPECT="${1:-auto}"

PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
info() { printf '        %s\n' "$1"; }

# --- preconditions ----------------------------------------------------------
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${PROXY}"; then
  echo "ERROR: proxy container '${PROXY}' is not running." >&2
  echo "       Start the QudoSSL stack first, e.g.:" >&2
  echo "         docker compose -f docker-compose.qudossl.yml up -d --build" >&2
  exit 2
fi
if ! docker exec "${PROXY}" sh -c 'command -v qudossl' >/dev/null 2>&1; then
  echo "ERROR: '${PROXY}' is the baseline (stock) proxy — it has no QudoSSL." >&2
  echo "       This check applies to the QudoSSL stack only." >&2
  exit 2
fi

# Detect the active build from the container's OPENSSL_CONF.
CONF="$(docker exec "${PROXY}" printenv OPENSSL_CONF 2>/dev/null || true)"
case "${CONF}" in
  *qudossl-fips.cnf) MODE="fips" ;;
  *)                 MODE="standard" ;;
esac
case "${EXPECT}" in
  --fips)     WANT="fips" ;;
  --standard) WANT="standard" ;;
  auto|"")    WANT="${MODE}" ;;
  *) echo "Unknown option: ${EXPECT} (use --standard or --fips)"; exit 2 ;;
esac

echo "QudoSSL HAProxy migration — verification"
echo "  Proxy container : ${PROXY}"
echo "  OPENSSL_CONF    : ${CONF:-<unset>}"
echo "  Detected build  : ${MODE}   (asserting: ${WANT})"
echo
if [[ "${WANT}" != "${MODE}" ]]; then
  bad "expected the ${WANT} build to be terminating TLS, but the container is running the ${MODE} build"
fi

# --- check 1: haproxy linked against QudoSSL --------------------------------
LDD="$(docker exec "${PROXY}" sh -c "ldd ${HAPROXY_BIN} 2>/dev/null | grep -E 'libssl|libcrypto'")"
if grep -q '/opt/qudossl/lib' <<<"${LDD}"; then
  ok "haproxy is linked against QudoSSL (/opt/qudossl/lib)"
else
  bad "haproxy is NOT linked against QudoSSL"
  info "ldd showed:"; sed 's/^/          /' <<<"${LDD}"
fi

# --- check 2: expected provider active --------------------------------------
PROV="$(docker exec "${PROXY}" qudossl list -providers 2>/dev/null)"
if [[ "${WANT}" == "fips" ]]; then
  if grep -q 'OpenSSL FIPS Provider' <<<"${PROV}" && grep -q 'OpenSSL Base Provider' <<<"${PROV}"; then
    ok "FIPS provider is active (FIPS + base)"
  else
    bad "FIPS provider is NOT active"
    info "providers:"; sed 's/^/          /' <<<"${PROV}"
  fi
else
  if grep -q 'OpenSSL Default Provider' <<<"${PROV}"; then
    ok "standard (default) provider is active"
  else
    bad "default provider is NOT active"
    info "providers:"; sed 's/^/          /' <<<"${PROV}"
  fi
fi

# --- helper: what group is negotiated when the client offers $1 ? -----------
# OpenSSL's s_client reports an ML-KEM hybrid as "Negotiated TLS1.3 group: NAME"
# but a classical ECDHE curve as "Peer Temp Key: ECDH, prime256v1, 256 bits".
# Parse whichever is present. (prime256v1 is OpenSSL's name for secp256r1.)
negotiated_group() {
  local out g
  out="$(docker exec "${PROXY}" sh -c \
    "echo | qudossl s_client -connect 127.0.0.1:443 -servername localhost -groups '$1' 2>/dev/null")"
  g="$(grep -m1 'Negotiated TLS1.3 group:' <<<"${out}" | sed 's/.*group: *//')"
  if [[ -z "${g}" ]]; then
    g="$(grep -m1 'Peer Temp Key: ECDH,' <<<"${out}" | sed -E 's/.*ECDH, *([^,]+),.*/\1/')"
  fi
  echo "${g}"
}

# --- check 3: hybrid list -> X25519MLKEM768 ---------------------------------
G_HYBRID="$(negotiated_group "${HYBRID}")"
if [[ "${G_HYBRID}" == "X25519MLKEM768" ]]; then
  ok "post-quantum group negotiated: X25519MLKEM768"
else
  bad "expected X25519MLKEM768, got '${G_HYBRID:-none}'"
fi

# --- check 4: classical-only offer -> classical (proves real negotiation) ---
G_CLASSICAL="$(negotiated_group "secp256r1")"
if [[ "${G_CLASSICAL}" == "secp256r1" || "${G_CLASSICAL}" == "prime256v1" ]]; then
  ok "classical fallback works: a classical-only client negotiates ${G_CLASSICAL} (= secp256r1)"
  info "Supported ≠ Negotiated: the server offers PQC but does not force it —"
  info "it negotiates the strongest group BOTH sides share."
else
  bad "classical-only client did not negotiate secp256r1 (got '${G_CLASSICAL:-none}')"
fi

# --- verdict ----------------------------------------------------------------
echo
if [[ ${FAIL} -eq 0 ]]; then
  printf '\033[32m===> RESULT: PASS\033[0m  (%d checks)  — QudoSSL post-quantum TLS is active (%s build).\n' "${PASS}" "${MODE}"
  exit 0
else
  printf '\033[31m===> RESULT: FAIL\033[0m  (%d passed, %d failed)\n' "${PASS}" "${FAIL}"
  exit 1
fi
