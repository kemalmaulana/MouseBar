#!/bin/bash
# Builds the Rust HID++ bridge (Rust/mousebar-logi) for arm64 macOS 14+ and wraps it
# as Vendor/MouseBarLogi.xcframework. Usage: Scripts/build-logi.sh
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="aarch64-apple-darwin"
MANIFEST="Rust/mousebar-logi/Cargo.toml"
LIB="Rust/mousebar-logi/target/$TARGET/release/libmousebar_logi.a"
XCFRAMEWORK="Vendor/MouseBarLogi.xcframework"

# rustup's default install puts cargo on PATH only through this file.
if ! command -v cargo >/dev/null 2>&1 && [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi
if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo not found. Install Rust with rustup: https://rustup.rs" >&2
    exit 1
fi

if command -v rustup >/dev/null 2>&1 && ! rustup target list --installed | grep -x "$TARGET" >/dev/null; then
    rustup target add "$TARGET"
fi

# `cargo rustc --crate-type staticlib`, not `cargo build`: the manifest also lists
# `rlib` (for examples/probe.rs), and with mixed crate types Cargo skips LTO and
# embeds LLVM bitcode in every object instead (54 MB vs 8.5 MB).
MACOSX_DEPLOYMENT_TARGET=14.0 cargo rustc --release --locked --target "$TARGET" \
    --manifest-path "$MANIFEST" --lib --crate-type staticlib

rm -rf "$XCFRAMEWORK"
mkdir -p Vendor
xcodebuild -create-xcframework \
    -library "$LIB" \
    -headers Rust/mousebar-logi/include \
    -output "$XCFRAMEWORK"

echo "xcframework: $(pwd)/$XCFRAMEWORK"
echo "static lib:  $(du -h "$LIB" | cut -f1) ($(stat -f %z "$LIB") bytes) $LIB"
