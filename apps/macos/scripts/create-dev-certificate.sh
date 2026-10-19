#!/usr/bin/env bash
# Creates a self-signed code signing certificate, "im Development", in your login keychain.
#
# Why: an ad-hoc signed app gets a new identity on every build, so the Keychain asks for
# permission to read im's GitHub token again after each rebuild. Signing with a stable
# certificate keeps the identity the same, so "Always Allow" sticks.
#
# The certificate only lives on this Mac and is only used to sign local builds.
# Remove it any time in Keychain Access (login keychain, "im Development").
set -euo pipefail

name="im Development"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
  echo "\"$name\" already exists."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$work/cert.cnf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
# A throwaway password: security import needs one, and the file is deleted right after.
openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
  -name "$name" -out "$work/im.p12" -passout pass:im
security import "$work/im.p12" -k "$keychain" -P im -T /usr/bin/codesign >/dev/null

echo "Created \"$name\". scripts/build-app.sh now signs with it."
