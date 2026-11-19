#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "Нет .env: создайте его из .env.example" >&2
    exit 1
fi
password=$(sed -n 's/^SEED_PASSWORD=//p' .env | tail -n 1)
if [ -z "$password" ]; then
    echo "SEED_PASSWORD в .env не задан" >&2
    exit 1
fi

hash=$(printf '%s' "$password" | docker compose exec -T identity python -c \
    'import sys; from argon2 import PasswordHasher; print(PasswordHasher().hash(sys.stdin.read()))')

run_sql() {
    docker compose exec -T postgres \
        psql -U postgres -d tusumba -v ON_ERROR_STOP=1 --single-transaction -q -t -A "$@"
}

run_sql -v password_hash="$hash" < seed/identity.sql
run_sql < seed/events.sql

echo "Тестовые данные загружены. Пароль пользователей - SEED_PASSWORD из .env."
