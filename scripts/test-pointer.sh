#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -parse-as-library -swift-version 5 \
  Sources/LumaTouch/PointerCapture.swift Sources/LumaTouch/TouchControlSurface.swift \
  Tests/LumaTouchTests/PointerCaptureSmoke.swift \
  -o .build/pointer-capture-smoke
exec .build/pointer-capture-smoke "$@"
