#!/bin/sh
set -eu

git_url=${TUSUMBA_GIT_URL:-https://github.com/tusumba}
target=$(cd "$(dirname "$0")/../.." && pwd)

for repo in identity-service events-service ticketing-service moderation-service notifications-service; do
    if [ -d "$target/$repo/.git" ]; then
        echo "$repo: уже склонирован, пропускаю"
    else
        git clone "$git_url/$repo.git" "$target/$repo"
    fi
done
