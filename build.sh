#!/usr/bin/env bash
# This file is part of ICU4X. For terms of use, please see the file
# called LICENSE at the top level of the ICU4X source tree
# (online at: https://github.com/unicode-org/icu4x/blob/main/LICENSE ).

set -e

# Set toolchain variable to a default if not defined
ICU4X_NIGHTLY_TOOLCHAIN="${ICU4X_NIGHTLY_TOOLCHAIN:-nightly-2022-04-05}"

# Install Rust toolchains
rustup toolchain install ${ICU4X_NIGHTLY_TOOLCHAIN}
rustup +${ICU4X_NIGHTLY_TOOLCHAIN} component add rust-src

# 100 KiB, working around a bug in older rustc
# https://github.com/unicode-org/icu4x/issues/2753
# keep in sync with .cargo/config.toml
WASM_STACK_SIZE=1000000

BASEDIR=$(dirname "$(realpath "$0")")
echo "BASEDIR: ${BASEDIR}"

# Don't regen the postcard data by default; delete the file to regen
if ! test -f "icu4x_data_skiawasm_bake"; then
    echo "Build WASM library with empty data"

    # Build the WASM library with an empty data provider
    RUSTFLAGS="-Cpanic=abort -Copt-level=s -C link-arg=-zstack-size=${WASM_STACK_SIZE} -Clinker-plugin-lto -Ccodegen-units=1 -C linker=${BASEDIR}/ld.py -C linker-flavor=wasm-ld" cargo +${ICU4X_NIGHTLY_TOOLCHAIN} build \
        -Z build-std=std,panic_abort -Z build-std-features=panic_immediate_abort \
        --target wasm32-unknown-unknown \
        --release \
        --package icu_capi_skiawasm \
        --features empty_data

    echo "Regen all data"

    # Regen all data
    cargo run --manifest-path ../../provider/datagen/Cargo.toml \
        --features=bin,experimental -- \
        --all-locales \
        --keys-for-bin target/wasm32-unknown-unknown/release/icu_capi_skiawasm.wasm \
        --cldr-tag 41.0.0 \
        --icuexport-tag release-72-1 \
        --format mod \
        --out ./icu4x_data_skiawasm_bake
fi

echo "Build WASM library with baked data"

# Build the WASM library, linking in the bake data
# TODO: This likely doesn't work if $BASEDIR has spaces
RUSTFLAGS="-Cpanic=abort -Copt-level=s -C link-arg=-zstack-size=${WASM_STACK_SIZE} -Clinker-plugin-lto -Ccodegen-units=1 -C linker=${BASEDIR}/ld.py -C linker-flavor=wasm-ld" cargo +${ICU4X_NIGHTLY_TOOLCHAIN} build \
    -Z build-std=std,panic_abort -Z build-std-features=panic_immediate_abort \
    --target wasm32-unknown-unknown \
    --release \
    --package icu_capi_skiawasm

cp target/wasm32-unknown-unknown/release/icu_capi_skiawasm.wasm icu_capi_skiawasm.wasm

echo "Refresh lib folder"

# Refresh the lib folder

rm -rf lib/*.js lib/*.d.ts

ICU4X_SHA="1d9c42cd543c08d2218e1fa99ca7fdd26fafe084"

while read file; do
    curl -sL https://raw.githubusercontent.com/unicode-org/icu4x/${ICU4X_SHA}/ffi/diplomat/js/include/${file} -o lib/${file}
done < lib/_files.txt
