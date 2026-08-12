#!/usr/bin/env bash

set -Eeuo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

command -v gh >/dev/null
command -v jq >/dev/null
[[ -n "${GITCODE_TOKEN:-}" ]] ||
    { printf '错误：缺少 GITCODE_TOKEN\n' >&2; exit 1; }
gh release view v1.0.4 --repo belleangelina/300X \
    --json body --jq .body >"$temporary_dir/notes.md"
gh release download v1.0.4 --repo belleangelina/300X \
    --dir "$temporary_dir/assets"
assets=()
for asset in "$temporary_dir"/assets/*
do
    [[ "$(basename "$asset")" == update-manifest.json ]] && continue
    assets+=("$asset")
done
((${#assets[@]} > 0)) || exit 1
GITCODE_TOKEN="${GITCODE_TOKEN:-}" GITCODE_TARGET=d6727b7ed011882c7fb379149263b064a90d3117 \
    "$project_dir/tool/release/sync_gitcode_release.sh" \
        v1.0.4 "$temporary_dir/notes.md" "${assets[@]}"
