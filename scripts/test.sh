#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
# A standalone runner keeps the tests usable with Command Line Tools alone;
# Apple's XCTest framework is supplied by full Xcode, absent on this Mac.
swiftc -parse-as-library -swift-version 5 \
  Sources/LumaTouch/PhoneBridge.swift Sources/LumaTouch/Morse.swift Sources/LumaTouch/AIClient.swift \
  Sources/LumaTouch/PDFReader.swift Sources/LumaTouch/Workspace.swift \
  Sources/LumaTouch/TouchControlSurface.swift \
  Sources/LumaTouch/Handwriting.swift Sources/LumaTouch/DrawnMorse.swift Sources/LumaTouch/AskAI.swift Sources/LumaTouch/MorseDrawingSurface.swift \
  Tests/LumaTouchTests/CoreTests.swift Tests/LumaTouchTests/ReaderControlTests.swift \
  Tests/LumaTouchTests/TouchControlTests.swift \
  Tests/LumaTouchTests/AskAITests.swift Tests/LumaTouchTests/HandwritingTests.swift Tests/LumaTouchTests/PhoneTests.swift \
  -o .build/core-tests
.build/core-tests
