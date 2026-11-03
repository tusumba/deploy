#!/bin/sh
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA public;
REVOKE ALL ON DATABASE tusumba FROM PUBLIC;
SQL

for service in identity events ticketing moderation notifications; do
    password=$(printenv "$(echo "$service" | tr '[:lower:]' '[:upper:]')_DB_PASSWORD")
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
        -v name="$service" -v password="$password" <<'SQL'
CREATE ROLE :"name" LOGIN PASSWORD :'password';
GRANT CONNECT, CREATE, TEMPORARY ON DATABASE tusumba TO :"name";
CREATE SCHEMA :"name" AUTHORIZATION :"name";
ALTER ROLE :"name" SET search_path = :"name", public;
SQL
done
