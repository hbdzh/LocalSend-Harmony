#!/bin/bash
# Build an ARM64 HarmonyOS HAP in a space-free temporary checkout.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
sdk_root="${DEVECO_SDK_HOME:?Set DEVECO_SDK_HOME to the DevEco SDK directory}"
native_sdk="$sdk_root/default/openharmony/native"
clang="$native_sdk/llvm/bin/aarch64-unknown-linux-ohos-clang"
if [[ ! -x "$clang" ]]; then
  echo "HarmonyOS ARM64 compiler not found: $clang" >&2
  exit 1
fi

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/localsend-ohos.XXXXXXXX")"
trap 'rm -rf "$temp_root"' EXIT
rsync -a --exclude .git --exclude .dart_tool --exclude build --exclude target \
  --exclude oh_modules --exclude .hvigor --exclude .cxx --exclude flutter_assets \
  "$root/" "$temp_root/"

# DevEco's local signing configuration may contain credentials and device
# specific paths. Keep it in ignored build output, not in the source tree.
local_signing="$root/app/build/harmony/signing-profile.local.json5"
if [[ -f "$local_signing" ]]; then
  cp "$local_signing" "$temp_root/app/ohos/build-profile.json5"
fi

export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$clang"
export CC_aarch64_unknown_linux_ohos="$clang"
export AR_aarch64_unknown_linux_ohos="$native_sdk/llvm/bin/llvm-ar"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${TMPDIR:-/tmp}/localsend-ohos-cargo}"

cd "$temp_root"
cargo build --locked --target aarch64-unknown-linux-ohos -p rust_lib_localsend_app
mkdir -p app/ohos/entry/libs/arm64-v8a
cp "$CARGO_TARGET_DIR/aarch64-unknown-linux-ohos/debug/librust_lib_localsend_app.so" \
  app/ohos/entry/libs/arm64-v8a/

# Keep the workspace's lockfile unchanged even when the shell selects a mirror.
env -u PUB_HOSTED_URL flutter pub get --enforce-lockfile
cd app
unsigned_hap="ohos/entry/build/default/outputs/default/entry-default-unsigned.hap"
signed_hap="ohos/entry/build/default/outputs/default/entry-default-signed.hap"
build_log="$temp_root/flutter-build.log"
if ! flutter build hap --debug --no-pub 2>&1 | tee "$build_log"; then
  # Flutter-OH emits this specific diagnostic after creating an unsigned HAP.
  if [[ ! -f "$unsigned_hap" ]] || ! grep -Fq '请通过DevEco Studio打开ohos工程后配置调试签名' "$build_log"; then
    exit 1
  fi
fi
mkdir -p "$root/app/build/harmony"
if [[ -f "$signed_hap" ]]; then
  cp "$signed_hap" "$root/app/build/harmony/localsend-arm64-signed.hap"
  echo "Signed HAP: $root/app/build/harmony/localsend-arm64-signed.hap"
else
  test -f "$unsigned_hap"
  cp "$unsigned_hap" "$root/app/build/harmony/localsend-arm64-unsigned.hap"
  echo "Unsigned HAP: $root/app/build/harmony/localsend-arm64-unsigned.hap"
  echo "Configure a HarmonyOS signing profile before installing on a device."
fi
