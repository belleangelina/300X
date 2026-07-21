#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLING_DIR="${X300_TOOLING_DIR:-$PROJECT_DIR/../.tooling}"
PUBSPEC_FILE="$PROJECT_DIR/pubspec.yaml"
RELEASE_DIR="$PROJECT_DIR/build/releases"

# 品牌与二进制标识
APP_DISPLAY_NAME="300X"
APP_FILE_PREFIX="X300"
LINUX_BINARY_NAME="x300"

platforms=()
artifacts=()
requested_version=""
requested_build_number=""
keep_version=false
log_file=""
android_sdk_root=""
aapt_bin=""
apksigner_bin=""
linux_arch=""
ios_source_ipa=""
android_universal_source=""
android_arm64_source=""

usage()
{
    printf '%s\n' \
        '用法：./build_release.sh [--platform PLATFORM] [选项]' \
        '' \
        '平台：android、linux、ios；可重复 --platform 为多个平台构建同一版本。' \
        '未指定 --platform 时默认构建 android。' \
        '默认将 1.2.3+4 更新为 1.2.4+5，全部构建成功后才写回 pubspec.yaml。' \
        '' \
        '选项：' \
        '  -p, --platform PLATFORM  构建平台，可重复使用（默认 android）' \
        '      --version X.Y.Z      指定新的版本名称，构建号仍默认递增' \
        '      --build-number N     指定新构建号，必须大于当前值' \
        '      --keep-version       保持版本名称，只递增构建号' \
        '      --log FILE           同时将完整日志写入指定文件' \
        '  -h, --help               显示帮助' \
        '' \
        '示例：' \
        '  ./build_release.sh                                # 默认 Android' \
        '  ./build_release.sh -p linux' \
        '  ./build_release.sh -p android -p linux --version 1.3.0' \
        '  ./build_release.sh --platform ios --keep-version' \
        '  ./build_release.sh --log /tmp/build.log'
}

fail()
{
    printf '错误：%s\n' "$1" >&2
    exit 1
}

add_platform()
{
    local platform="$1"
    case "$platform" in
        android|linux|ios)
            ;;
        *)
            fail "不支持的平台：$platform"
            ;;
    esac
    local existing
    for existing in "${platforms[@]:-}"
    do
        if [[ "$existing" == "$platform" ]]
        then
            return
        fi
    done
    platforms+=("$platform")
}

has_platform()
{
    local expected="$1"
    local platform
    for platform in "${platforms[@]}"
    do
        if [[ "$platform" == "$expected" ]]
        then
            return 0
        fi
    done
    return 1
}

version_is_newer()
{
    local left="$1"
    local right="$2"
    local -a left_parts
    local -a right_parts
    local index
    local left_value
    local right_value
    IFS='.' read -r -a left_parts <<<"$left"
    IFS='.' read -r -a right_parts <<<"$right"
    for index in 0 1 2 3
    do
        left_value="${left_parts[index]:-0}"
        right_value="${right_parts[index]:-0}"
        if ((10#$left_value != 10#$right_value))
        then
            ((10#$left_value > 10#$right_value))
            return
        fi
    done
    return 1
}

find_flutter()
{
    if [[ -n "${FLUTTER_BIN:-}" ]]
    then
        printf '%s\n' "$FLUTTER_BIN"
    elif [[ -x "$TOOLING_DIR/flutter/bin/flutter" ]]
    then
        printf '%s\n' "$TOOLING_DIR/flutter/bin/flutter"
    elif command -v flutter >/dev/null
    then
        command -v flutter
    else
        fail '找不到 Flutter，请设置 FLUTTER_BIN'
    fi
}

configure_android()
{
    if [[ -z "${JAVA_HOME:-}" && -x "$TOOLING_DIR/jdk/current/bin/java" ]]
    then
        export JAVA_HOME="$TOOLING_DIR/jdk/current"
    fi
    if [[ -n "${JAVA_HOME:-}" ]]
    then
        export PATH="$JAVA_HOME/bin:$PATH"
    fi
    command -v java >/dev/null || fail 'Android 构建需要 Java 17'
    command -v unzip >/dev/null || fail 'Android 产物校验需要 unzip'

    android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$TOOLING_DIR/android-sdk}}"
    [[ -d "$android_sdk_root" ]] ||
        fail "Android SDK 不存在：$android_sdk_root"
    export ANDROID_SDK_ROOT="$android_sdk_root"
    export ANDROID_HOME="$android_sdk_root"
    if [[ -z "${ANDROID_USER_HOME:-}" && -d "$TOOLING_DIR/android-home" ]]
    then
        export ANDROID_USER_HOME="$TOOLING_DIR/android-home"
    fi

    local selected_version=""
    local candidate
    local candidate_version
    for candidate in "$android_sdk_root"/build-tools/*
    do
        [[ -d "$candidate" ]] || continue
        candidate_version="${candidate##*/}"
        [[ "$candidate_version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || continue
        if [[ -z "$selected_version" ]] ||
                version_is_newer "$candidate_version" "$selected_version"
        then
            selected_version="$candidate_version"
        fi
    done
    [[ -n "$selected_version" ]] || fail 'Android SDK 中没有 build-tools'
    aapt_bin="$android_sdk_root/build-tools/$selected_version/aapt"
    apksigner_bin="$android_sdk_root/build-tools/$selected_version/apksigner"
    [[ -x "$aapt_bin" ]] || fail "aapt 不可执行：$aapt_bin"
    [[ -x "$apksigner_bin" ]] ||
        fail "apksigner 不可执行：$apksigner_bin"
}

verify_android_apk()
{
    local apk="$1"
    local expected_abis="$2"
    local actual_abis
    local badging
    local native_listing
    local package_line
    badging="$("$aapt_bin" dump badging "$apk")"
    package_line="$(sed -n '1p' <<<"$badging")"
    [[ "$package_line" == *"versionCode='$next_build_number'"* ]] ||
        fail "APK versionCode 与预期不符：$package_line"
    [[ "$package_line" == *"versionName='$next_version_name'"* ]] ||
        fail "APK versionName 与预期不符：$package_line"
    actual_abis="$(
        sed -n "s/^native-code: //p" <<<"$badging" |
            tr -d "'" |
            tr ' ' '\n' |
            sed '/^$/d' |
            sort |
            tr '\n' ' '
    )"
    expected_abis="$(
        tr ' ' '\n' <<<"$expected_abis" |
            sed '/^$/d' |
            sort |
            tr '\n' ' '
    )"
    [[ "$actual_abis" == "$expected_abis" ]] ||
        fail "APK ABI 与预期不符：$apk"
    native_listing="$(unzip -Z -v "$apk" 'lib/*/*.so')"
    if grep -q 'compression method:.*none (stored)' <<<"$native_listing"
    then
        fail "APK 仍包含未压缩的原生库：$apk"
    fi
    if [[ -n "$log_file" ]]
    then
        "$apksigner_bin" verify --verbose "$apk" >>"$log_file" 2>&1 ||
            fail "APK 签名校验失败，详情见 $log_file"
    else
        "$apksigner_bin" verify --verbose "$apk" ||
            fail "APK 签名校验失败：$apk"
    fi
}

configure_linux()
{
    [[ "$(uname -s)" == Linux ]] || fail 'Linux Release 只能在 Linux 上构建'
    command -v tar >/dev/null || fail 'Linux Release 打包需要 tar'
    command -v pkg-config >/dev/null || fail 'Linux Release 构建需要 pkg-config'
    case "$(uname -m)" in
        x86_64|amd64)
            linux_arch='x64'
            ;;
        aarch64|arm64)
            linux_arch='arm64'
            ;;
        riscv64)
            linux_arch='riscv64'
            ;;
        *)
            fail "不支持的 Linux 架构：$(uname -m)"
            ;;
    esac
    local local_pkg_config_path=""
    local candidate
    if [[ -d "$TOOLING_DIR/pkgconfig" ]]
    then
        local_pkg_config_path="$TOOLING_DIR/pkgconfig"
    fi
    for candidate in \
        "$TOOLING_DIR"/linux-sysroot/usr/lib/*/pkgconfig \
        "$TOOLING_DIR"/linux-sysroot/usr/lib/pkgconfig \
        "$TOOLING_DIR"/linux-sysroot/usr/share/pkgconfig
    do
        [[ -d "$candidate" ]] || continue
        local_pkg_config_path="${local_pkg_config_path:+$local_pkg_config_path:}$candidate"
    done
    if [[ -n "$local_pkg_config_path" ]]
    then
        export PKG_CONFIG_PATH="$local_pkg_config_path${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    fi
    pkg-config --exists 'libsecret-1 >= 0.18.4' ||
        fail 'Linux Release 构建需要 libsecret-1 开发文件'
}

configure_ios()
{
    [[ "$(uname -s)" == Darwin ]] || fail 'iOS Release 只能在 macOS/Xcode 环境构建'
    command -v xcodebuild >/dev/null || fail 'iOS Release 构建需要 Xcode'
}

write_version()
{
    local current="$1"
    local next="$2"
    CURRENT_VERSION="$current" NEXT_VERSION="$next" perl -0pi -e '
        my $old = quotemeta $ENV{CURRENT_VERSION};
        my $count = s/^version:[ \t]*$old[ \t]*$/version: $ENV{NEXT_VERSION}/m;
        die "version replacement failed\n" unless $count == 1;
    ' "$PUBSPEC_FILE"
    grep -qx "version: $next" "$PUBSPEC_FILE" ||
        fail '发布产物已生成，但 pubspec.yaml 版本写回校验失败'
}

checksum_for()
{
    local file="$1"
    if command -v sha256sum >/dev/null
    then
        sha256sum "$file" | awk '{ print $1 }'
    else
        shasum -a 256 "$file" | awk '{ print $1 }'
    fi
}

while (($# > 0))
do
    case "$1" in
        -p|--platform)
            (($# >= 2)) || fail '--platform 缺少参数'
            add_platform "$2"
            shift 2
            ;;
        --version)
            (($# >= 2)) || fail '--version 缺少参数'
            requested_version="$2"
            shift 2
            ;;
        --build-number)
            (($# >= 2)) || fail '--build-number 缺少参数'
            requested_build_number="$2"
            shift 2
            ;;
        --keep-version)
            keep_version=true
            shift
            ;;
        --log)
            (($# >= 2)) || fail '--log 缺少参数'
            log_file="$2"
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

if ((${#platforms[@]} == 0))
then
    platforms=(android)
fi
[[ -z "$requested_version" || "$keep_version" == false ]] ||
    fail '--version 与 --keep-version 不能同时使用'
[[ -f "$PUBSPEC_FILE" ]] || fail "找不到 $PUBSPEC_FILE"
command -v perl >/dev/null || fail '缺少 perl，无法安全写回版本号'

current_version="$(awk '/^version:[[:space:]]*/ { print $2; exit }' "$PUBSPEC_FILE")"
if [[ ! "$current_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]
then
    fail "无法解析 pubspec.yaml 版本：$current_version"
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
current_build_number="${BASH_REMATCH[4]}"

if [[ -n "$requested_version" ]]
then
    [[ "$requested_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "版本名称必须为 X.Y.Z：$requested_version"
    next_version_name="$requested_version"
elif [[ "$keep_version" == true ]]
then
    next_version_name="$major.$minor.$patch"
else
    next_version_name="$major.$minor.$((10#$patch + 1))"
fi

if [[ -n "$requested_build_number" ]]
then
    [[ "$requested_build_number" =~ ^[1-9][0-9]*$ ]] ||
        fail "构建号必须为正整数：$requested_build_number"
    next_build_number="$requested_build_number"
else
    next_build_number="$((10#$current_build_number + 1))"
fi
((10#$next_build_number > 10#$current_build_number)) ||
    fail "新构建号必须大于当前值 $current_build_number"
next_version="$next_version_name+$next_build_number"

flutter_bin="$(find_flutter)"
[[ -x "$flutter_bin" ]] || fail "Flutter 不可执行：$flutter_bin"
if [[ -z "${PUB_CACHE:-}" && -d "$TOOLING_DIR/pub-cache" ]]
then
    export PUB_CACHE="$TOOLING_DIR/pub-cache"
fi
has_platform android && configure_android
has_platform linux && configure_linux
has_platform ios && configure_ios

mkdir -p "$RELEASE_DIR"
if [[ -n "$log_file" ]]
then
    mkdir -p "$(dirname "$log_file")"
    : >"$log_file"
fi
platform_label="$(IFS=-; printf '%s' "${platforms[*]}")"

printf '正在构建 %s Release：%s -> %s（%s）\n' \
    "$APP_DISPLAY_NAME" "$current_version" "$next_version" "$platform_label"
if [[ -n "$log_file" ]]
then
    printf '完整日志：%s\n' "$log_file"
fi

# 运行子命令，stdout/stderr 直通终端；显式 --log 时同时 tee 到文件
run_step()
{
    local label="$1"
    shift
    printf '\n==> %s\n' "$label"
    if [[ -n "$log_file" ]]
    then
        printf '\n[%s]\n' "$label" >>"$log_file"
        "$@" 2>&1 | tee -a "$log_file"
        return "${PIPESTATUS[0]}"
    else
        "$@"
    fi
}

for platform in "${platforms[@]}"
do
    case "$platform" in
        android)
            if ! (
                cd "$PROJECT_DIR"
                run_step "Android 通用 APK" \
                    "$flutter_bin" build apk --release \
                        --build-name="$next_version_name" \
                        --build-number="$next_build_number"
            )
            then
                printf 'Android 构建失败，pubspec.yaml 未修改。\n' >&2
                exit 1
            fi
            android_universal_source="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
            [[ -f "$android_universal_source" ]] ||
                fail "找不到 Android 通用 APK：$android_universal_source"
            android_universal_staged="$PROJECT_DIR/build/app/outputs/flutter-apk/${LINUX_BINARY_NAME}-universal-release.apk"
            cp "$android_universal_source" "$android_universal_staged"
            android_universal_source="$android_universal_staged"
            verify_android_apk \
                "$android_universal_source" \
                "armeabi-v7a arm64-v8a x86_64"

            if ! (
                cd "$PROJECT_DIR"
                run_step "Android arm64 APK" \
                    "$flutter_bin" build apk --release \
                        --target-platform android-arm64 \
                        --android-project-arg x300TargetAbi=arm64-v8a \
                        --android-project-arg disable-abi-filtering=true \
                        --build-name="$next_version_name" \
                        --build-number="$next_build_number"
            )
            then
                printf 'Android arm64 构建失败，pubspec.yaml 未修改。\n' >&2
                exit 1
            fi
            android_arm64_source="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
            [[ -f "$android_arm64_source" ]] ||
                fail "找不到 Android arm64 APK：$android_arm64_source"
            verify_android_apk "$android_arm64_source" "arm64-v8a"
            ;;
        linux)
            rm -f "$PROJECT_DIR/build/linux/$linux_arch/release/CMakeCache.txt"
            if ! (
                cd "$PROJECT_DIR"
                run_step "Linux Release" \
                    "$flutter_bin" build linux --release \
                        --build-name="$next_version_name" \
                        --build-number="$next_build_number"
            )
            then
                printf 'Linux 构建失败，pubspec.yaml 未修改。\n' >&2
                exit 1
            fi
            linux_bundle="$PROJECT_DIR/build/linux/$linux_arch/release/bundle"
            [[ -x "$linux_bundle/$LINUX_BINARY_NAME" ]] ||
                fail "找不到 Linux Release bundle：$linux_bundle"
            ;;
        ios)
            if ! (
                cd "$PROJECT_DIR"
                run_step "iOS IPA" \
                    "$flutter_bin" build ipa --release \
                        --build-name="$next_version_name" \
                        --build-number="$next_build_number"
            )
            then
                printf 'iOS 构建失败，pubspec.yaml 未修改。\n' >&2
                exit 1
            fi
            ios_candidates=("$PROJECT_DIR"/build/ios/ipa/*.ipa)
            [[ -f "${ios_candidates[0]}" ]] ||
                fail '构建完成但找不到 iOS IPA'
            ios_source_ipa="${ios_candidates[0]}"
            ;;
    esac
done

for platform in "${platforms[@]}"
do
    case "$platform" in
        android)
            artifact="$RELEASE_DIR/$APP_FILE_PREFIX-v$next_version_name-android-universal-release.apk"
            cp "$android_universal_source" "$artifact"
            artifacts+=("$artifact")
            artifact="$RELEASE_DIR/$APP_FILE_PREFIX-v$next_version_name-android-arm64-v8a-release.apk"
            cp "$android_arm64_source" "$artifact"
            ;;
        linux)
            artifact="$RELEASE_DIR/$APP_FILE_PREFIX-v$next_version_name-linux-$linux_arch-release.tar.gz"
            tar -C "$PROJECT_DIR/build/linux/$linux_arch/release/bundle" \
                -czf "$artifact" .
            ;;
        ios)
            artifact="$RELEASE_DIR/$APP_FILE_PREFIX-v$next_version_name-ios-release.ipa"
            cp "$ios_source_ipa" "$artifact"
            ;;
    esac
    artifacts+=("$artifact")
done

write_version "$current_version" "$next_version"

{
    printf '构建成功。\n版本：%s\n' "$next_version"
    for artifact in "${artifacts[@]}"
    do
        size_bytes="$(wc -c <"$artifact" | tr -d ' ')"
        checksum="$(checksum_for "$artifact")"
        printf '产物：%s\n大小：%s 字节\nSHA-256：%s\n' \
            "$artifact" "$size_bytes" "$checksum"
    done
    if [[ -n "$log_file" ]]
    then
        printf '日志：%s\n' "$log_file"
    fi
}
