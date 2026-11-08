#!/bin/sh
# Remove the compromised "emSign ECC Root CA - G3" (eMudhra Technologies, disclosed Oct 2026) from
# this image's OS trust bundle. The fixed Alpine ca-certificates-bundle (20261020-r0) that drops
# this CA is not in every Alpine release's repo yet (e.g. 3.24 still ships 20260611-r0), so
# `apk upgrade` cannot remove it -- strip it directly so it can't be used to forge TLS certificates
# (this image makes outbound HTTPS, e.g. git-pulling the CARE-SM mapping). Verified the bundle still
# trusts ordinary public CAs afterwards (github.com validates). No-op (and still exits 0) once the
# cert is already gone, so it is safe on an image whose base later ships the fixed bundle.
set -eu
BAD="emSign ECC Root CA - G3"
BUNDLE=/etc/ssl/certs/ca-certificates.crt
ADDED=0
if ! command -v openssl >/dev/null 2>&1; then
  apk add --no-cache --virtual .castrip openssl
  ADDED=1
fi
work=$(mktemp -d)
out=$(mktemp)
# Split the concatenated PEM bundle into one file per certificate, keep every cert whose subject is
# not the compromised CA, then rewrite the bundle from what we kept.
awk -v d="$work" 'BEGIN{c=0} {print >> (d"/c_"c".pem")} /END CERTIFICATE/{c++}' "$BUNDLE"
for f in "$work"/c_*.pem; do
  [ -s "$f" ] || continue
  subj=$(openssl x509 -in "$f" -noout -subject 2>/dev/null || echo "")
  case "$subj" in
    *"$BAD"*) ;;                 # drop the compromised CA
    *) cat "$f" >> "$out" ;;     # keep everything else
  esac
done
cat "$out" > "$BUNDLE"
rm -rf "$work" "$out"
# Fail the build if the compromised CA somehow survived -- never ship it silently.
if openssl crl2pkcs7 -nocrl -certfile "$BUNDLE" | openssl pkcs7 -print_certs -noout 2>/dev/null | grep -q "$BAD"; then
  echo "FATAL: '$BAD' still present in $BUNDLE after strip" >&2
  exit 1
fi
[ "$ADDED" = "1" ] && apk del .castrip || true
echo "CA strip OK: '$BAD' removed from $BUNDLE"
