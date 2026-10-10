#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
# A standalone runner keeps the tests usable with Command Line Tools alone;
# Apple's XCTest framework is supplied by full Xcode, absent on this Mac.
swiftc -parse-as-library -swift-version 5 \
  Sources/LumaTouch/Morse.swift Sources/LumaTouch/AIClient.swift \
  Sources/LumaTouch/PDFReader.swift Tests/LumaTouchTests/CoreTests.swift \
  -o .build/core-tests
.build/core-tests
