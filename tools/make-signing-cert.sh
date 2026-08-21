#!/bin/zsh
# Creates a self-signed code-signing certificate in the login keychain so
# Swatch Monster keeps a stable code identity across rebuilds.
#
# Why this exists: an ad-hoc signature (`codesign -s -`) is derived from the
# binary, so every rebuild produces a different identity. macOS treats that as a
# different app and revokes Screen Recording, which silently disables the zoom
# loupe and looks like a lost feature. Signing with a certificate keeps the
# identity constant, so the permission you grant once survives future rebuilds.
#
# Run once. Safe to re-run: it stops if the identity already exists.
#
# To undo: open Keychain Access, search "Swatch Monster Local Signing", delete
# both the certificate and its private key. build.sh then falls back to ad-hoc.

set -euo pipefail

NAME="Swatch Monster Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "==> \"$NAME\" already exists — nothing to do."
    security find-identity -v -p codesigning | grep "$NAME"
    exit 0
fi

WORK=$(mktemp -d)
# The private key ends up in the keychain; don't leave copies on disk.
trap 'rm -rf "$WORK"' EXIT

echo "==> Generating certificate"
cat > "$WORK/openssl.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = codesign
prompt             = no

[ dn ]
CN = $NAME

[ codesign ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -config "$WORK/openssl.cnf" 2>/dev/null

# macOS `security` cannot read the PKCS#12 defaults that current LibreSSL
# emits, and it dislikes empty passwords — hence the legacy algorithms below.
openssl pkcs12 -export \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/identity.p12" \
    -passout pass:swatchmonster -name "$NAME" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES 2>/dev/null

echo "==> Importing into the login keychain"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P swatchmonster \
    -T /usr/bin/codesign -A >/dev/null

# Without code-signing trust the identity imports but is not usable, and
# `find-identity` reports zero valid identities. This step may ask for your
# login password.
echo "==> Marking it trusted for code signing (may prompt for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "==> Done"
security find-identity -v -p codesigning | grep "$NAME"
echo ""
echo "Now run ./build.sh install, then grant Screen Recording once."
