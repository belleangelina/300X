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
target="${GITCODE_TARGET:-main}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "非法标签：$tag"
[[ -s "$notes_file" ]] || fail "发布说明为空：$notes_file"
for asset in "$@"
do
    [[ -f "$asset" ]] || fail "找不到附件：$asset"
done

api='https://api.gitcode.com/api/v5/repos/belleangelina/300X'
auth_header="Authorization: Bearer $GITCODE_TOKEN"

release_json="$(curl -sS -H "$auth_header" "$api/releases/tags/$tag")"
if ! jq -e '.tag_name' <<<"$release_json" >/dev/null 2>&1
then
    release_json="$(
        jq -n \
            --arg tag "$tag" \
            --arg name "$tag" \
            --arg target "$target" \
            --rawfile body "$notes_file" \
            '{tag_name:$tag,name:$name,body:$body,target_commitish:$target,
                release_status:"latest"}' |
            curl -fsS -X POST -H "$auth_header" \
                -H 'Content-Type: application/json' \
                --data-binary @- "$api/releases"
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
    local expected_size
    local expected_sha256
    local remote_file
    local remote_sha256
    local remote_size
    local upload_json
    local upload_url
    local header_file
    local -a curl_args
    name="$(basename "$asset")"
    expected_size="$(wc -c <"$asset" | tr -d ' ')"
    expected_sha256="$(sha256sum "$asset" | awk '{ print $1 }')"
    existing="$(jq -r --arg name "$name" \
        '.assets[]? | select(.name == $name) | .browser_download_url' \
        <<<"$release_json" | head -1)"
    if [[ -n "$existing" ]]
    then
        remote_file="$(mktemp)"
        curl -fsSL -o "$remote_file" "$existing"
        remote_size="$(wc -c <"$remote_file" | tr -d ' ')"
        remote_sha256="$(sha256sum "$remote_file" | awk '{ print $1 }')"
        if [[ "$remote_size" != "$expected_size" ||
            "$remote_sha256" != "$expected_sha256" ]]
        then
            rm -f "$remote_file"
            fail "GitCode 同名附件内容不一致：$name"
        fi
        rm -f "$remote_file"
        return
    fi
    upload_json="$(curl -fsS -G -H "$auth_header" \
        --data-urlencode "file_name=$name" "$api/releases/$tag/upload_url")"
    upload_url="$(jq -er '.url' <<<"$upload_json")"
    header_file="$(mktemp)"
    jq -r '.headers // {} | to_entries[] | "\(.key): \(.value)"' \
        <<<"$upload_json" >"$header_file"
    curl_args=(-fsS -X PUT --data-binary "@$asset")
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
