#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build verification
python3 - <<'PY'
from pathlib import Path
for name in ['phone-test-link.txt', 'phone-test-finished']:
    Path('.build', name).unlink(missing_ok=True)
PY
swiftc -parse-as-library -swift-version 5 Sources/LumaTouch/PhoneBridge.swift Tests/LumaTouchTests/PhoneTransportHarness.swift -o .build/phone-harness
.build/phone-harness &
harness_pid=$!
trap 'kill "$harness_pid" 2>/dev/null || true' EXIT
for attempt in {1..50}; do
    if [ -f .build/phone-test-link.txt ]; then break; fi
    sleep 0.1
done
# Requires Node and Playwright (NODE_PATH may point to an existing installation).
node scripts/test-phone.cjs
wait "$harness_pid"
