#!/usr/bin/env bash

set -Eeuo pipefail

fail()
{
    printf '错误：%s\n' "$1" >&2
    exit 1
}

[[ $# -ge 3 ]] || fail '用法：sync_gitcode_release.sh TAG NOTES_FILE ASSET...'
[[ -n "${GITCODE_TOKEN:-}" ]] || fail '缺少 GITCODE_TOKEN'
command -v curl >/dev/null || fail '缺少 curl'
command -v jq >/dev/null || fail '缺少 jq'

tag="$1"
notes_file="$2"
shift 2
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "非法标签：$tag"
[[ -s "$notes_file" ]] || fail "发布说明为空：$notes_file"
for asset in "$@"
do
    [[ -f "$asset" ]] || fail "找不到附件：$asset"
done

git fetch --quiet --force https://github.com/belleangelina/300X.git \
    "refs/tags/$tag:refs/tags/$tag"
[[ "$(git cat-file -t "refs/tags/$tag")" == tag ]] ||
    fail "GitHub 标签不是注解标签：$tag"
tag_ref="$(git rev-parse "refs/tags/$tag")"
api_root='https://api.gitcode.com/api/v5'
remote_tag="$(git ls-remote https://gitcode.com/belleangelina/300X.git \
    "refs/tags/$tag" | awk '{ print $1 }')"
[[ "$remote_tag" == "$tag_ref" ]] ||
    fail "GitCode 镜像尚未同步标签：$tag"

api="$api_root/repos/belleangelina/300X"

release_json="$(curl -sS -G \
    --data-urlencode "access_token=$GITCODE_TOKEN" \
    "$api/releases/tags/$tag")"
if ! jq -e '.tag_name' <<<"$release_json" >/dev/null 2>&1
then
    prerelease_json='false'
    release_status='latest'
    if [[ "${GITCODE_PRERELEASE:-}" == 'true' ]]
    then
        prerelease_json='true'
        release_status='prerelease'
    fi
    release_json="$(
        jq -n \
            --arg tag "$tag" \
            --arg name "$tag" \
            --rawfile body "$notes_file" \
            --argjson prerelease "$prerelease_json" \
            --arg release_status "$release_status" \
            '{tag_name:$tag,name:$name,body:$body,prerelease:$prerelease,release_status:$release_status}' |
            curl -fsS -X POST \
                --url-query "access_token=$GITCODE_TOKEN" \
                -H 'Content-Type: application/json' \
                --data-binary @- "$api/releases"
    )"
fi
if [[ "$(jq -r .name <<<"$release_json")" != "$tag" ||
    "$(jq -r .body <<<"$release_json")" != "$(cat "$notes_file")" ]]
then
    release_json="$(
        jq -n \
            --arg tag "$tag" \
            --arg name "$tag" \
            --rawfile body "$notes_file" \
            '{tag_name:$tag,name:$name,body:$body}' |
            curl -fsS -X PATCH \
                --url-query "access_token=$GITCODE_TOKEN" \
                -H 'Content-Type: application/json' \
                --data-binary @- "$api/releases/$tag"
    )"
fi
[[ "$(jq -r .tag_name <<<"$release_json")" == "$tag" &&
    "$(jq -r .name <<<"$release_json")" == "$tag" &&
    "$(jq -r .body <<<"$release_json")" == "$(cat "$notes_file")" ]] ||
    fail "GitCode Release 标题或说明不一致：$tag"

upload_asset()
{
    local asset="$1"
    local name
    local existing
    local existing_id
    local expected_md5
    local expected_size
    local remote_etag
    local remote_size
    local upload_json
    local upload_url
    local header_file
    local -a curl_args
    name="$(basename "$asset")"
    expected_size="$(wc -c <"$asset" | tr -d ' ')"
    expected_md5="$(md5sum "$asset" | awk '{ print $1 }')"
    existing="$(jq -c --arg name "$name" \
        '[.assets[]? | select(.name == $name)][0] // empty' \
        <<<"$release_json")"
    if [[ -n "$existing" ]]
    then
        header_file="$(mktemp)"
        curl -fsSIL -D "$header_file" -o /dev/null \
            "$api/releases/$tag/attach_files/$name/download"
        remote_size="$(awk \
            'tolower($1) == "content-length:" \
                { value=$2 } END \
                { gsub(/[[:space:]]/, "", value); print value }' \
            "$header_file")"
        remote_etag="$(awk \
            'tolower($1) == "etag:" \
                { value=$2 } END \
                { gsub(/[[:space:]"]/, "", value); print value }' \
            "$header_file")"
        rm -f "$header_file"
        if [[ "$remote_size" == "$expected_size" &&
            "$remote_etag" == "$expected_md5" ]]
        then
            return
        fi
        existing_id="$(jq -er .id <<<"$existing")"
        curl -fsS -X DELETE \
            --url-query "access_token=$GITCODE_TOKEN" \
            "$api/releases/$tag/attach_files/$existing_id"
    fi
    upload_json="$(curl -fsS -G \
        --data-urlencode "access_token=$GITCODE_TOKEN" \
        --data-urlencode "file_name=$name" "$api/releases/$tag/upload_url")"
    upload_url="$(jq -er '.url' <<<"$upload_json")"
    header_file="$(mktemp)"
    jq -r '.headers // {} | to_entries[] | "\(.key): \(.value)"' \
        <<<"$upload_json" >"$header_file"
    curl_args=(
        -fsS --max-time 600 --retry 2 --retry-delay 5 --retry-all-errors
        -X PUT --data-binary "@$asset"
    )
    while IFS= read -r header
    do
        [[ -n "$header" ]] && curl_args+=(-H "$header")
    done <"$header_file"
    curl "${curl_args[@]}" "$upload_url" >/dev/null
    rm -f "$header_file"
}

for asset in "$@"
do
    [[ "$(basename "$asset")" == 'update-manifest.json' ]] && continue
    upload_asset "$asset"
done
for asset in "$@"
do
    [[ "$(basename "$asset")" == 'update-manifest.json' ]] || continue
    upload_asset "$asset"
done
