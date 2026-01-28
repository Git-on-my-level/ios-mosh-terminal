#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS_DIR="$ROOT_DIR/Frameworks"
BUILD_DIR="$ROOT_DIR/build/xcframeworks"
SRC_DIR="$BUILD_DIR/src"
OPENSSL_SRC="$SRC_DIR/openssl"
LIBSSH2_SRC="$SRC_DIR/libssh2"

DEPLOYMENT_TARGET=${DEPLOYMENT_TARGET:-"17.0"}
OPENSSL_REF="openssl-3.0.14"
LIBSSH2_REF="libssh2-1.11.0"

JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

require_cmd git
require_cmd cmake
require_cmd xcodebuild
require_cmd xcrun
require_cmd make
require_cmd lipo
require_cmd rsync
require_cmd perl

fetch_repo() {
  local name="$1"
  local url="$2"
  local ref="$3"
  local dest="$4"

  if [ ! -d "$dest/.git" ]; then
    echo "Cloning $name..."
    git clone "$url" "$dest"
  fi

  (
    cd "$dest"
    git fetch --tags --force
    git checkout -f "$ref"
    git clean -fdx
  )
}

prepare_build_dir() {
  local src="$1"
  local dest="$2"
  rm -rf "$dest"
  mkdir -p "$dest"
  rsync -a --exclude .git "$src/" "$dest/"
}

build_openssl_arch() {
  local sdk="$1"
  local target="$2"
  local arch="$3"
  local min_flag="$4"
  local build_root="$5"

  local build_dir="$build_root/${sdk}-${arch}"
  prepare_build_dir "$OPENSSL_SRC" "$build_dir"

  pushd "$build_dir" >/dev/null
  export CC="$(xcrun --sdk "$sdk" --find clang)"
  export CFLAGS="-arch $arch $min_flag"
  export LDFLAGS="-arch $arch $min_flag"

  ./Configure "$target" no-shared no-dso no-tests --prefix="$build_dir/install"
  make -j"$JOBS"
  make install_sw
  popd >/dev/null
}

build_openssl() {
  local openssl_build_dir="$BUILD_DIR/openssl"
  mkdir -p "$openssl_build_dir"

  echo "Building OpenSSL ($OPENSSL_REF)..."
  build_openssl_arch "iphoneos" "ios64-xcrun" "arm64" "-miphoneos-version-min=$DEPLOYMENT_TARGET" "$openssl_build_dir"
  build_openssl_arch "iphonesimulator" "iossimulator-xcrun" "arm64" "-mios-simulator-version-min=$DEPLOYMENT_TARGET" "$openssl_build_dir"
  build_openssl_arch "iphonesimulator" "iossimulator-xcrun" "x86_64" "-mios-simulator-version-min=$DEPLOYMENT_TARGET" "$openssl_build_dir"

  local device_prefix="$openssl_build_dir/iphoneos-arm64/install"
  local sim_arm64_prefix="$openssl_build_dir/iphonesimulator-arm64/install"
  local sim_x86_64_prefix="$openssl_build_dir/iphonesimulator-x86_64/install"
  local sim_universal_prefix="$openssl_build_dir/iphonesimulator-universal"

  mkdir -p "$sim_universal_prefix/lib"
  rsync -a "$sim_arm64_prefix/include/" "$sim_universal_prefix/include/"

  lipo -create \
    "$sim_arm64_prefix/lib/libcrypto.a" \
    "$sim_x86_64_prefix/lib/libcrypto.a" \
    -output "$sim_universal_prefix/lib/libcrypto.a"

  lipo -create \
    "$sim_arm64_prefix/lib/libssl.a" \
    "$sim_x86_64_prefix/lib/libssl.a" \
    -output "$sim_universal_prefix/lib/libssl.a"

  echo "$device_prefix" > "$openssl_build_dir/device_prefix"
  echo "$sim_universal_prefix" > "$openssl_build_dir/sim_prefix"
}

build_libssh2() {
  local openssl_device_prefix="$1"
  local openssl_sim_prefix="$2"
  local libssh2_build_dir="$BUILD_DIR/libssh2"

  echo "Building libssh2 ($LIBSSH2_REF)..."

  local device_build="$libssh2_build_dir/iphoneos"
  rm -rf "$device_build"
  cmake -S "$LIBSSH2_SRC" -B "$device_build" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_ZLIB_COMPRESSION=OFF \
    -DCRYPTO_BACKEND=OpenSSL \
    -DOPENSSL_ROOT_DIR="$openssl_device_prefix" \
    -DOPENSSL_INCLUDE_DIR="$openssl_device_prefix/include" \
    -DOPENSSL_SSL_LIBRARY="$openssl_device_prefix/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl_device_prefix/lib/libcrypto.a"
  cmake --build "$device_build" -- -j"$JOBS"

  local sim_build="$libssh2_build_dir/iphonesimulator"
  rm -rf "$sim_build"
  cmake -S "$LIBSSH2_SRC" -B "$sim_build" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_ZLIB_COMPRESSION=OFF \
    -DCRYPTO_BACKEND=OpenSSL \
    -DOPENSSL_ROOT_DIR="$openssl_sim_prefix" \
    -DOPENSSL_INCLUDE_DIR="$openssl_sim_prefix/include" \
    -DOPENSSL_SSL_LIBRARY="$openssl_sim_prefix/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl_sim_prefix/lib/libcrypto.a"
  cmake --build "$sim_build" -- -j"$JOBS"

  echo "$device_build" > "$libssh2_build_dir/device_build"
  echo "$sim_build" > "$libssh2_build_dir/sim_build"
}

find_libssh2_library() {
  local build_dir="$1"
  if [ -f "$build_dir/src/libssh2.a" ]; then
    echo "$build_dir/src/libssh2.a"
  elif [ -f "$build_dir/lib/libssh2.a" ]; then
    echo "$build_dir/lib/libssh2.a"
  else
    echo ""
  fi
}

find_libssh2_config() {
  local build_dir="$1"
  if [ -f "$build_dir/src/libssh2_config.h" ]; then
    echo "$build_dir/src/libssh2_config.h"
  elif [ -f "$build_dir/include/libssh2_config.h" ]; then
    echo "$build_dir/include/libssh2_config.h"
  elif [ -f "$build_dir/libssh2_config.h" ]; then
    echo "$build_dir/libssh2_config.h"
  else
    echo ""
  fi
}

create_xcframeworks() {
  mkdir -p "$FRAMEWORKS_DIR"

  local openssl_build_dir="$BUILD_DIR/openssl"
  local libssh2_build_dir="$BUILD_DIR/libssh2"
  local openssl_device_prefix
  local openssl_sim_prefix
  openssl_device_prefix=$(cat "$openssl_build_dir/device_prefix")
  openssl_sim_prefix=$(cat "$openssl_build_dir/sim_prefix")

  local libssh2_device_build
  local libssh2_sim_build
  libssh2_device_build=$(cat "$libssh2_build_dir/device_build")
  libssh2_sim_build=$(cat "$libssh2_build_dir/sim_build")

  local libssh2_device_lib
  local libssh2_sim_lib
  libssh2_device_lib=$(find_libssh2_library "$libssh2_device_build")
  libssh2_sim_lib=$(find_libssh2_library "$libssh2_sim_build")

  if [ -z "$libssh2_device_lib" ] || [ -z "$libssh2_sim_lib" ]; then
    echo "Failed to locate libssh2 static libraries." >&2
    exit 1
  fi

  local libssh2_headers="$libssh2_build_dir/headers"
  rm -rf "$libssh2_headers"
  mkdir -p "$libssh2_headers"
  rsync -a "$LIBSSH2_SRC/include/" "$libssh2_headers/"
  local libssh2_config
  libssh2_config=$(find_libssh2_config "$libssh2_device_build")
  if [ -z "$libssh2_config" ]; then
    libssh2_config=$(find_libssh2_config "$libssh2_sim_build")
  fi
  if [ -z "$libssh2_config" ]; then
    echo "Failed to locate libssh2_config.h." >&2
    exit 1
  fi
  cp "$libssh2_config" "$libssh2_headers/libssh2_config.h"

  mkdir -p "$libssh2_headers/openssl"
  rsync -a "$openssl_device_prefix/include/openssl/" "$libssh2_headers/openssl/"
  cat <<'MODULE' > "$libssh2_headers/module.modulemap"
module libssh2 [system] {
  umbrella "."
  export *
}
MODULE

  rm -rf "$FRAMEWORKS_DIR/libcrypto.xcframework" \
    "$FRAMEWORKS_DIR/libssl.xcframework" \
    "$FRAMEWORKS_DIR/libssh2.xcframework"

  xcodebuild -create-xcframework \
    -library "$openssl_device_prefix/lib/libcrypto.a" -headers "$openssl_device_prefix/include" \
    -library "$openssl_sim_prefix/lib/libcrypto.a" -headers "$openssl_sim_prefix/include" \
    -output "$FRAMEWORKS_DIR/libcrypto.xcframework"

  xcodebuild -create-xcframework \
    -library "$openssl_device_prefix/lib/libssl.a" -headers "$openssl_device_prefix/include" \
    -library "$openssl_sim_prefix/lib/libssl.a" -headers "$openssl_sim_prefix/include" \
    -output "$FRAMEWORKS_DIR/libssl.xcframework"

  xcodebuild -create-xcframework \
    -library "$libssh2_device_lib" -headers "$libssh2_headers" \
    -library "$libssh2_sim_lib" -headers "$libssh2_headers" \
    -output "$FRAMEWORKS_DIR/libssh2.xcframework"
}

main() {
  mkdir -p "$SRC_DIR"

  fetch_repo "OpenSSL" "https://github.com/openssl/openssl.git" "$OPENSSL_REF" "$OPENSSL_SRC"
  fetch_repo "libssh2" "https://github.com/libssh2/libssh2.git" "$LIBSSH2_REF" "$LIBSSH2_SRC"

  build_openssl
  local openssl_device_prefix
  local openssl_sim_prefix
  openssl_device_prefix=$(cat "$BUILD_DIR/openssl/device_prefix")
  openssl_sim_prefix=$(cat "$BUILD_DIR/openssl/sim_prefix")

  build_libssh2 "$openssl_device_prefix" "$openssl_sim_prefix"
  create_xcframeworks

  echo "XCFrameworks are available under $FRAMEWORKS_DIR"
}

main "$@"
