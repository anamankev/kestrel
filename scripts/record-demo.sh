#!/bin/zsh
# Records the scripted product tour (DemoTour.swift) from a booted iPad simulator.
# usage: scripts/record-demo.sh <simulator-udid>
# Needs a Release build of Kestrel installed on that simulator. Output: build/demo-raw.mp4
set -e
DEV=${1:?simulator udid}
mkdir -p build
xcrun simctl terminate "$DEV" dev.kestrel.terminal 2>/dev/null || true
xcrun simctl io "$DEV" recordVideo --codec h264 --force build/demo-raw.mp4 &
REC=$!
sleep 2
xcrun simctl launch "$DEV" dev.kestrel.terminal -demo >/dev/null
sleep 64
kill -INT $REC; wait $REC
# Rotate to landscape, trim the launch, export 720p MP4 + README GIF (no ffmpeg needed):
swift scripts/postprocess-demo.swift build/demo-raw.mp4 build/kestrel-demo.mp4 docs/media/demo.gif 10 15 -90
