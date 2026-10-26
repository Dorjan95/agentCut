#!/usr/bin/env bash
# Genera il progetto, compila, installa in /Applications e avvia agentCut.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project agentCut.xcodeproj -scheme agentCut -configuration Debug \
  -derivedDataPath build build | tail -n 20

pkill -x agentCut || true
ditto build/Build/Products/Debug/agentCut.app /Applications/agentCut.app
/System/Library/CoreServices/pbs -update
open /Applications/agentCut.app
