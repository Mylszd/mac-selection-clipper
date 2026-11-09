#!/bin/bash
# Creates a LOCAL self-signed code-signing identity in the login keychain.
#
# Why: ad-hoc signatures change on every rebuild, so macOS forgets the
# Accessibility permission each time. With a stable certificate, the app's
# designated requirement (bundle ID + certificate) stays the same across
# rebuilds and the permission survives. This is for local builds only; it is
# NOT an Apple Developer ID and does not notarize anything.
#
# Usage: ./scripts/create-signing-identity.sh ["Certificate Name"]
#   CLIPPER_SIGN_BACKUP_DIR=dir  also keep a .p12 backup (+ password file) there.
# macOS may ask for your login password (trust settings) once, and the first
# codesign may ask to use the key: choose "Always Allow".
set -euo pipefail
NAME="${1:-Mac Selection Clipper Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "Already exists and valid: $NAME"; exit 0
fi
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
OPENSSL=/usr/bin/openssl   # system LibreSSL: produces a .p12 that `security import` accepts
cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/identity.p12" -passout "pass:$PASS"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
echo "Marking the certificate as trusted for code signing (macOS may ask for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
if [[ -n "${CLIPPER_SIGN_BACKUP_DIR:-}" ]]; then
    mkdir -p "$CLIPPER_SIGN_BACKUP_DIR"; chmod 700 "$CLIPPER_SIGN_BACKUP_DIR"
    cp "$WORK/identity.p12" "$CLIPPER_SIGN_BACKUP_DIR/$NAME.p12"
    printf '%s\n' "$PASS" > "$CLIPPER_SIGN_BACKUP_DIR/$NAME.p12.password"
    chmod 600 "$CLIPPER_SIGN_BACKUP_DIR/$NAME".p12*
    echo "Backup: $CLIPPER_SIGN_BACKUP_DIR/$NAME.p12"
fi
security find-identity -v -p codesigning | grep "\"$NAME\""
echo "Done. ./scripts/build.sh will now sign with \"$NAME\" automatically."
