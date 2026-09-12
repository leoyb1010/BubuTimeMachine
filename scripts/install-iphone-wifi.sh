#!/usr/bin/env bash
# 在带 Xcode 的开发机（GUI 登录会话内）执行：构建真机 Debug 包并经 Wi-Fi 覆盖安装到已配对 iPhone。
# 覆盖安装保持同 bundle id + 同签名，不卸载、不清数据（2.14 起的数据保护副本策略见 docs/RELEASE_2.14.0.md）。
#
# 用法：
#   scripts/install-iphone-wifi.sh                 # 自动挑第一台 available (paired) 的 iPhone
#   DEVICE=<devicectl identifier> scripts/install-iphone-wifi.sh
#
# 前提：
#   1) iPhone 与本机同一 Wi-Fi，且已在 Xcode 里配对并信任（xcrun devicectl list devices 里 State=available）。
#   2) 本机登录钥匙串可用（SSH 会话里 codesign 会报 errSecInternalComponent，需在 GUI 终端运行，
#      或先 `security unlock-keychain ~/Library/Keychains/login.keychain-db`）。
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/bin:$PATH

BUNDLE_ID=com.bubu.timemachine
DD="${DERIVED_DATA:-$HOME/code/bubu-dd-device}"

if [[ -z "${DEVICE:-}" ]]; then
  DEVICE=$(xcrun devicectl list devices --hide-headers 2>/dev/null \
    | awk '/iPhone/ && /available/ {print $(NF-3)}' | grep -E '^[0-9A-F-]{36}$' | head -1 || true)
fi
if [[ -z "${DEVICE:-}" ]]; then
  echo "没有 available (paired) 的 iPhone。确认手机亮屏、同一 Wi-Fi、已配对，然后重试：xcrun devicectl list devices" >&2
  exit 2
fi
echo "目标设备：$DEVICE"

xcodegen generate >/dev/null
xcodebuild -project BubuTimeMachine.xcodeproj -scheme BubuTimeMachine \
  -destination "generic/platform=iOS" -allowProvisioningUpdates \
  -derivedDataPath "$DD" build 2>&1 | tee /tmp/bubu-device-build.log \
  | grep -E ": error:|BubuTimeMachine.*: warning:|BUILD SUCCEEDED|BUILD FAILED" | sort -u

APP="$DD/Build/Products/Debug-iphoneos/BubuTimeMachine.app"
[[ -d "$APP" ]] || { echo "找不到 $APP" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
echo "安装 $VERSION ($BUILD) → $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID" || true
# 回读安装版本，作为覆盖安装的证据
xcrun devicectl device info apps --device "$DEVICE" --bundle-id "$BUNDLE_ID" 2>/dev/null | grep -E "$BUNDLE_ID|version" || true
echo "INSTALL_OK $VERSION ($BUILD)"
