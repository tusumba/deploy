#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

[ -f .env ] || cp .env.example .env
mkdir -p secrets

if [ ! -f secrets/jwt-private.pem ]; then
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out secrets/jwt-private.pem
    chmod 600 secrets/jwt-private.pem
fi
openssl pkey -in secrets/jwt-private.pem -pubout -out secrets/jwt-public.pem

key=$(awk '{printf "%s\\n", $0}' secrets/jwt-public.pem)
grep -v '^JWT_PUBLIC_KEY=' .env > .env.tmp || true
printf "JWT_PUBLIC_KEY='%s'\n" "$key" >> .env.tmp
mv .env.tmp .env

echo "Ключи: secrets/jwt-private.pem, secrets/jwt-public.pem. JWT_PUBLIC_KEY записан в .env."
