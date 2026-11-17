#!/bin/sh
set -eu

git_url=${TUSUMBA_GIT_URL:-https://github.com/tusumba}
target=$(cd "$(dirname "$0")/../.." && pwd)
. "$(dirname "$0")/repos.sh"

for repo in $REPOS; do
    if [ -d "$target/$repo/.git" ]; then
        echo "$repo: уже склонирован, пропускаю"
    else
        git clone "$git_url/$repo.git" "$target/$repo"
    fi
done
