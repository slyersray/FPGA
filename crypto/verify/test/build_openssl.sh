#!/usr/bin/env bash
# 把设计说明第 2 节钉住的 OpenSSL 提交编成静态 libcrypto，安装到 crypto/verify/work。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="$ROOT/crypto/verify/work"
COMMIT="2506f1fc323b567b0e48a13b6069c7778077e55e"
PREFIX="$WORK/openssl-install"
SRC="$WORK/openssl-src"

if [[ -f "$PREFIX/COMMIT" && "$(cat "$PREFIX/COMMIT")" == "$COMMIT" && -f "$PREFIX/lib/libcrypto.a" ]]; then
    echo "openssl already built at $COMMIT"
    exit 0
fi

mkdir -p "$WORK"
rm -rf "$SRC" "$PREFIX"
echo "downloading openssl $COMMIT"
curl -fL --retry 3 -o "$WORK/openssl.tar.gz" \
    "https://codeload.github.com/openssl/openssl/tar.gz/${COMMIT}"
tar -xzf "$WORK/openssl.tar.gz" -C "$WORK"
mv "$WORK/openssl-${COMMIT}" "$SRC"
rm -f "$WORK/openssl.tar.gz"

cd "$SRC"
./Configure linux-x86_64 \
    --prefix="$PREFIX" \
    --libdir=lib \
    no-shared \
    no-tests
make -j"$(nproc)" build_libs
make -j"$(nproc)" install_dev
echo "$COMMIT" > "$PREFIX/COMMIT"
echo "OPENSSL_BUILD_OK $COMMIT"
