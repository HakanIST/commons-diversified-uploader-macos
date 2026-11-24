#!/bin/sh
# Resmî NuGet paketinden ONNX Runtime'ı indirir ve Frameworks/onnxruntime.xcframework olarak paketler.
set -eu
VERSION="${ORT_VERSION:-1.32.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Frameworks/onnxruntime.xcframework"
[ -d "$OUT" ] && [ "${1:-}" != "--force" ] && { echo "Zaten var: $OUT"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fL -o "$TMP/ort.nupkg" "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/$VERSION/microsoft.ml.onnxruntime.$VERSION.nupkg"
unzip -q "$TMP/ort.nupkg" 'runtimes/osx-arm64/native/*' 'build/native/include/*' -d "$TMP/pkg"
mkdir -p "$TMP/include"
cp "$TMP/pkg/build/native/include/"onnxruntime_c_api.h "$TMP/pkg/build/native/include/"onnxruntime_error_code.h "$TMP/pkg/build/native/include/"onnxruntime_ep_c_api.h "$TMP/pkg/build/native/include/"onnxruntime_ep_device_ep_metadata_keys.h "$TMP/include/" 2>/dev/null || true
cat > "$TMP/include/module.modulemap" <<'MAP'
module onnxruntime {
  header "onnxruntime_c_api.h"
  link "onnxruntime"
  export *
}
MAP
DYLIB="$TMP/pkg/runtimes/osx-arm64/native/libonnxruntime.dylib"
install_name_tool -id "@rpath/libonnxruntime.dylib" "$DYLIB"
codesign --force --sign - "$DYLIB"
rm -rf "$OUT"; mkdir -p "$ROOT/Frameworks"
xcodebuild -create-xcframework -library "$DYLIB" -headers "$TMP/include" -output "$OUT"
