#!/bin/sh
# Сборка без SwiftPM (на Command Line Tools без Xcode swift build может не работать).
# Универсальный бинарник: Intel + Apple Silicon.
set -e
cd "$(dirname "$0")"
mkdir -p .build
for arch in x86_64 arm64; do
  swiftc -O -target $arch-apple-macos11 Sources/k530diag/*.swift -o .build/k530diag-$arch
done
lipo -create .build/k530diag-x86_64 .build/k530diag-arm64 -output .build/k530diag
echo "Готово: $(pwd)/.build/k530diag"
