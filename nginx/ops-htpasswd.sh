#!/bin/sh
set -eu

case "$OPS_USER" in
    *:*) echo "OPS_USER не должен содержать двоеточие" >&2; exit 1 ;;
esac

hash=$(printf '%s' "$OPS_PASSWORD" | cryptpw -m sha512)
printf '%s:%s\n' "$OPS_USER" "$hash" > /etc/nginx/ops.htpasswd
chmod 640 /etc/nginx/ops.htpasswd
chgrp nginx /etc/nginx/ops.htpasswd
