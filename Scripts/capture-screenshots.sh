#!/usr/bin/env bash
# Captures the App Store screenshots from the real app on an iPhone Pro Max simulator (the 6.9" size).
# Needs macOS with Xcode and `xcodegen`. Usage: Scripts/capture-screenshots.sh [output-dir]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/screenshots}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
# ${OUT:?} aborts instead of expanding to /*.png if OUT were ever empty.
rm -f "${OUT:?}"/*.png

# Newest available "iPhone NN Pro Max" simulator.
UDID="$(python3 - <<'PY'
import json, re, subprocess, sys
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
best = None
for runtime, devices in data["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        model = re.fullmatch(r"iPhone (\d+) Pro Max", device["name"])
        if model:
            key = (version, int(model.group(1)))
            if best is None or key > best[0]:
                best = (key, device["udid"], device["name"])
if best is None:
    raise SystemExit("no 'iPhone NN Pro Max' simulator is available")
print("using", best[2], file=sys.stderr)
print(best[1])
PY
)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
# A clean status bar, as in Apple's own marketing screenshots.
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4 --operatorName ""

xcodegen generate

rm -rf build/screenshots.xcresult
TEST_RUNNER_SCREENSHOT_DIR="$OUT" xcodebuild test \
  -project FlagQuiz.xcodeproj -scheme FlagQuizScreenshots \
  -destination "id=$UDID" \
  -resultBundlePath build/screenshots.xcresult \
  CODE_SIGNING_ALLOWED=NO

COUNT="$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')"
if [ "$COUNT" -lt 6 ]; then
  echo "expected 6 screenshots, found $COUNT in $OUT" >&2
  exit 1
fi
for f in "$OUT"/*.png; do
  echo "$(basename "$f"): $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/ {printf "%s ", $2}')"
done
