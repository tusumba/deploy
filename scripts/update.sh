#!/bin/sh
set -eu

main() {
    cd "$(dirname "$0")/.."
    . scripts/repos.sh

    ./scripts/clone.sh >/dev/null
    for repo in deploy $REPOS; do
        git -C "../$repo" fetch -q origin main
        git -C "../$repo" merge -q --ff-only origin/main
    done

    state=$(for repo in deploy $REPOS; do echo "$repo $(git -C "../$repo" rev-parse --short HEAD)"; done)
    if [ "$state" = "$(cat .deployed 2>/dev/null || true)" ]; then
        return 0
    fi

    export BUILDX_NO_DEFAULT_ATTESTATIONS=1
    export NGINX_CONFIG_REV="$(git rev-parse HEAD:nginx)"
    export GATUS_CONFIG_REV="$(git rev-parse HEAD:gatus)"
    export CADDY_CONFIG_REV="$(git rev-parse HEAD:caddy)"

    skip=""
    for repo in $REPOS; do
        [ -f "../$repo/Dockerfile" ] || skip="$skip ${repo%-service} ${repo%-service}-migrate"
    done
    targets=$(docker compose config --services | grep -vxF "$(printf '%s\n' $skip)")

    echo "Обновляю стенд:"
    echo "$state"
    [ -z "$skip" ] || echo "Без Dockerfile, пропускаю:$skip"
    docker compose up -d --build --wait --remove-orphans $targets
    printf '%s\n' "$state" > .deployed
    docker image prune -f >/dev/null
    echo "Стенд обновлён"
}

main "$@"; exit
