#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_root="$(cd "${script_dir}/.." && pwd)"
build_root="${FOCUS_BREAKS_BUILD_ROOT:-${package_root}/.build}"
app_bundle="${build_root}/FocusBreaks.app"
contents_dir="${app_bundle}/Contents"
cache_root="${build_root}/caches"

install -d -m 0700 \
    "${cache_root}/clang" \
    "${cache_root}/swiftpm" \
    "${cache_root}/config" \
    "${cache_root}/security"

env CLANG_MODULE_CACHE_PATH="${cache_root}/clang" swift build \
    --disable-sandbox \
    --package-path "${package_root}" \
    --scratch-path "${build_root}" \
    --cache-path "${cache_root}/swiftpm" \
    --config-path "${cache_root}/config" \
    --security-path "${cache_root}/security" \
    --manifest-cache local \
    --configuration release \
    --product FocusBreaks
env CLANG_MODULE_CACHE_PATH="${cache_root}/clang" swift build \
    --disable-sandbox \
    --package-path "${package_root}" \
    --scratch-path "${build_root}" \
    --cache-path "${cache_root}/swiftpm" \
    --config-path "${cache_root}/config" \
    --security-path "${cache_root}/security" \
    --manifest-cache local \
    --configuration release \
    --product focusctl

install -d -m 0755 "${contents_dir}/MacOS" "${contents_dir}/Helpers"
install -m 0755 "${build_root}/release/FocusBreaks" "${contents_dir}/MacOS/FocusBreaks"
install -m 0755 "${build_root}/release/focusctl" "${contents_dir}/Helpers/focusctl"
install -m 0644 "${package_root}/Config/Info.plist" "${contents_dir}/Info.plist"

codesign \
    --force \
    --sign - \
    --entitlements "${package_root}/Config/FocusBreaks.entitlements" \
    "${app_bundle}"
codesign --verify --deep --strict "${app_bundle}"

printf '%s\n' "${app_bundle}"
