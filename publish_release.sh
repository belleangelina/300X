#!/usr/bin/env bash

set -Eeuo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pubspec_file="$project_dir/pubspec.yaml"
version_name=""
build_number=""
message=""
notes_file=""
retry_tag=""
notes_mode=""

fail()
{
    printf '错误：%s\n' "$1" >&2
    exit 1
}

usage()
{
    printf '%s\n' \
        '用法：./publish_release.sh [选项] (-m MESSAGE | -n FILE)' \
        '' \
        '  -v, --version X.Y.Z    指定版本并创建版本提交' \
        '  -b, --build-number N   指定构建号，仅可与 -v 同用' \
        '  -m, --message TEXT     直接提供发布说明' \
        '  -n, --notes-file FILE  从文件读取发布说明' \
        '      --retry TAG        复用尚未创建 Release 的失败标签' \
        '  -h, --help             显示帮助'
}

while (($# > 0))
do
    case "$1" in
        -v|--version)
            (($# >= 2)) || fail "$1 缺少参数"
            version_name="$2"
            shift 2
            ;;
        -b|--build-number)
            (($# >= 2)) || fail "$1 缺少参数"
            build_number="$2"
            shift 2
            ;;
        -m|--message)
            (($# >= 2)) || fail "$1 缺少参数"
            [[ -z "$notes_mode" ]] || fail '-m 与 -n 必须且只能指定一个'
            message="$2"
            notes_mode=message
            shift 2
            ;;
        -n|--notes-file)
            (($# >= 2)) || fail "$1 缺少参数"
            [[ -z "$notes_mode" ]] || fail '-m 与 -n 必须且只能指定一个'
            notes_file="$2"
            notes_mode=file
            shift 2
            ;;
        --retry)
            (($# >= 2)) || fail '--retry 缺少参数'
            retry_tag="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "未知参数：$1"
            ;;
    esac
done

[[ -n "$notes_mode" ]] || fail '-m 与 -n 必须且只能指定一个'
if [[ "$notes_mode" == file ]]
then
    [[ -s "$notes_file" ]] || fail "发布说明文件为空：$notes_file"
    grep -q '[^[:space:]]' "$notes_file" || fail "发布说明文件为空：$notes_file"
    notes_file="$(cd "$(dirname "$notes_file")" && pwd)/$(basename "$notes_file")"
else
    [[ -n "${message//[[:space:]]/}" ]] || fail '发布说明不能为空'
    notes_file="$(mktemp)"
    trap 'rm -f "$notes_file"' EXIT
    printf '%s\n' "$message" >"$notes_file"
fi

[[ -z "$build_number" || -n "$version_name" ]] ||
    fail '-b 只能与 -v 同用'
[[ -z "$retry_tag" || -z "$version_name$build_number" ]] ||
    fail '--retry 不能与 -v 或 -b 同用'
[[ "$(git -C "$project_dir" branch --show-current)" == main ]] ||
    fail '只能从 main 分支发布'
[[ -z "$(git -C "$project_dir" status --porcelain)" ]] ||
    fail '工作区存在未提交修改'
git -C "$project_dir" fetch --quiet origin main --tags
[[ "$(git -C "$project_dir" rev-parse HEAD)" == \
    "$(git -C "$project_dir" rev-parse origin/main)" ]] ||
    fail '本地 main 必须与 origin/main 完全一致'

current="$(awk '/^version:[[:space:]]*/ { print $2; exit }' "$pubspec_file")"
[[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([1-9][0-9]*)$ ]] ||
    fail "无法解析当前版本：$current"
current_name="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
current_build="${BASH_REMATCH[4]}"

if [[ -n "$version_name" ]]
then
    [[ "$version_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail '版本必须为 X.Y.Z'
    if [[ -z "$build_number" ]]
    then
        build_number="$((10#$current_build + 1))"
    fi
    [[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail '构建号必须为正整数'
    ((10#$build_number > 10#$current_build)) ||
        fail "构建号必须大于 $current_build"
    next="$version_name+$build_number"
    tag="v$version_name"
elif [[ -n "$retry_tag" ]]
then
    [[ "$retry_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "非法重试标签：$retry_tag"
    tag="$retry_tag"
    [[ "$tag" == "v$current_name" ]] ||
        fail "重试标签与当前 pubspec 版本不一致：v$current_name"
    if gh release view "$tag" --repo belleangelina/300X >/dev/null 2>&1
    then
        fail "GitHub 已存在 $tag Release，禁止复用"
    fi
    gitcode_status="$(curl -sS -o /dev/null -w '%{http_code}' \
        "https://api.gitcode.com/api/v5/repos/belleangelina/300X/releases/tags/$tag")"
    [[ "$gitcode_status" == 400 || "$gitcode_status" == 404 ]] ||
        fail "GitCode 可能已存在 $tag Release，禁止复用"
    next="$current"
else
    tag="v$current_name"
    next="$current"
fi

if [[ -z "$retry_tag" ]]
then
    git -C "$project_dir" rev-parse "$tag" >/dev/null 2>&1 &&
        fail "标签已存在：$tag"
    gh release view "$tag" --repo belleangelina/300X >/dev/null 2>&1 &&
        fail "GitHub Release 已存在：$tag"
fi

printf '即将发布：%s（%s）\n' "$tag" "$next"
printf '发布说明：\n'
sed -n '1,20p' "$notes_file"
printf '推送 main 和标签将触发 Android/iOS 构建及双站发布。继续？[y/N] '
read -r answer
[[ "$answer" == y || "$answer" == Y ]] || fail '已取消发布'

if [[ -n "$retry_tag" ]]
then
    git -C "$project_dir" tag -d "$tag" >/dev/null 2>&1 || true
    if git -C "$project_dir" ls-remote --exit-code --tags origin \
        "refs/tags/$tag" >/dev/null 2>&1
    then
        git -C "$project_dir" push origin ":refs/tags/$tag"
    fi
elif [[ -n "$version_name" ]]
then
    CURRENT_VERSION="$current" NEXT_VERSION="$next" perl -0pi -e '
        my $old = quotemeta $ENV{CURRENT_VERSION};
        my $count = s/^version:[ \t]*$old[ \t]*$/version: $ENV{NEXT_VERSION}/m;
        die "version replacement failed\n" unless $count == 1;
    ' "$pubspec_file"
    git -C "$project_dir" add pubspec.yaml
    git -C "$project_dir" commit -m "chore: release v$version_name"
fi

git -C "$project_dir" tag -a "$tag" -F "$notes_file"
git -C "$project_dir" push --atomic origin main "$tag"
printf '已推送 %s，GitHub Actions 将开始正式发布。\n' "$tag"
