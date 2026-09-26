#!/bin/bash
set -euo pipefail
# Populate ONLY a simulator photo library for real PhotosPicker end-to-end tests.
# Existing photos are never removed. No family material or network is involved.
simulator_id="${1:?Usage: bash scripts/prepare-school-picker-fixtures.sh SIMULATOR_UDID}"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
xcrun simctl bootstatus "$simulator_id" -b >/dev/null
command -v ffmpeg >/dev/null || { echo 'ffmpeg is required to generate the two-second test video.' >&2; exit 1; }
fixture_dir="$(mktemp -d /tmp/bubu-picker-fixture.XXXXXX)"
trap 'rm -f "$fixture_dir/video.mp4" "$fixture_dir/report.jpg"; rmdir "$fixture_dir"' EXIT
ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=0xf8c7d4:s=640x480:d=2 \
  -c:v libx264 -pix_fmt yuv420p "$fixture_dir/video.mp4"
swift "$project_root/scripts/SchoolPickerFixture.swift" "$fixture_dir/report.jpg"
xcrun simctl addmedia "$simulator_id" "$fixture_dir/report.jpg" "$fixture_dir/video.mp4"
