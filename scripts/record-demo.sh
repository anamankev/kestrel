#!/bin/zsh
# Records the scripted walkthrough (DemoTour.swift) from a booted iPad simulator.
# usage: scripts/record-demo.sh <simulator-udid> [trim-seconds]
# Needs a Debug build of Kestrel installed on that simulator (the tour is compiled out of
# Release). The tour uses a throwaway account, opens on the subscribe page and logs DEMO DONE.
# Output: build/kestrel-walkthrough.mp4 (1080p) and docs/media/demo.gif (README preview).
set -e
DEV=${1:?simulator udid}
TRIM=${2:-19}          # seconds of app launch to cut; check the first frames if launch is slower
mkdir -p build
LOG="$(xcrun simctl get_app_container "$DEV" dev.kestrel.terminal data)/tmp/kestrel-snapshots/log.txt"
rm -f "$LOG"
xcrun simctl terminate "$DEV" dev.kestrel.terminal 2>/dev/null || true
xcrun simctl io "$DEV" recordVideo --codec h264 --force build/walkthrough-raw.mp4 &
REC=$!
sleep 2
xcrun simctl launch "$DEV" dev.kestrel.terminal -demo >/dev/null
for i in {1..150}; do grep -q "DEMO DONE" "$LOG" 2>/dev/null && break; sleep 3; done
sleep 1
kill -INT $REC; wait $REC
# Rotate to landscape, cut the launch, export 1080p MP4 + a 15 s README GIF of the terminal:
swift scripts/postprocess-demo.swift build/walkthrough-raw.mp4 build/kestrel-walkthrough.mp4 docs/media/demo.gif $((TRIM + 12)) 15 -90 $TRIM
