#!/usr/bin/env bash

set -Eeuo pipefail

fail()
{
    printf '错误：%s\n' "$1" >&2
    exit 1
}

[[ $# -eq 1 ]] || fail '用法：push_gitcode_tag.sh TAG'
[[ -n "${GITCODE_TOKEN:-}" ]] || fail '缺少 GITCODE_TOKEN'
command -v git >/dev/null || fail '缺少 git'

tag="$1"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "非法标签：$tag"

git fetch --quiet --force origin "refs/tags/$tag:refs/tags/$tag"
[[ "$(git cat-file -t "refs/tags/$tag")" == tag ]] ||
    fail "不是注解标签：$tag"

askpass="$(mktemp)"
cleanup()
{
    rm -f "$askpass"
}
trap cleanup EXIT
cat > "$askpass" << 'ASKPASS'
#!/bin/sh
case "$1" in
    *[Uu]sername*) printf '%s\n' 'belleangelina' ;;
    *) printf '%s\n' "$GITCODE_TOKEN" ;;
esac
ASKPASS
chmod 700 "$askpass"

GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= \
    push --porcelain https://gitcode.com/belleangelina/300X.git \
    "refs/tags/$tag:refs/tags/$tag"
