#!/bin/sh
set -eu
umask 077

cd "$(dirname "$0")/.."

[ -f .env ] || cp .env.example .env
mkdir -p secrets

if [ ! -f secrets/jwt-private.pem ]; then
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out secrets/jwt-private.pem
    chmod 600 secrets/jwt-private.pem
fi
openssl pkey -in secrets/jwt-private.pem -pubout -out secrets/jwt-public.pem

one_line() {
    awk '{printf "%s\\n", $0}' "$1"
}

grep -v -e '^JWT_PUBLIC_KEY=' -e '^JWT_PRIVATE_KEY=' .env > .env.tmp || true
printf "JWT_PUBLIC_KEY='%s'\n" "$(one_line secrets/jwt-public.pem)" >> .env.tmp
printf "JWT_PRIVATE_KEY='%s'\n" "$(one_line secrets/jwt-private.pem)" >> .env.tmp
mv .env.tmp .env

echo "Ключи: secrets/jwt-private.pem, secrets/jwt-public.pem. JWT_PUBLIC_KEY и JWT_PRIVATE_KEY записаны в .env."
