#!/usr/bin/env bash
set -euo pipefail

project="${1:-BubuTimeMachine.xcodeproj}"
user_name="${USER:-$(id -un)}"
plist="$project/xcuserdata/$user_name.xcuserdatad/xcschemes/xcschememanagement.plist"
pbxproj="$project/project.pbxproj"

mkdir -p "$(dirname "$plist")"

if [[ ! -f "$plist" ]]; then
  cat > "$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>SchemeUserState</key>
  <dict>
    <key>BubuTimeMachine.xcscheme_^#shared#^_</key>
    <dict>
      <key>orderHint</key>
      <integer>0</integer>
    </dict>
  </dict>
</dict>
</plist>
PLIST
fi

target_uuid() {
  local target="$1"
  awk -v target="$target" '
    /Begin PBXNativeTarget section/ { inside = 1 }
    /End PBXNativeTarget section/ { inside = 0 }
    inside && index($0, "/* " target " */ = {") { print $1; exit }
  ' "$pbxproj"
}

plistbuddy=/usr/libexec/PlistBuddy

"$plistbuddy" -c "Delete :SchemeUserState:BubuWidgetsExtension.xcscheme_^#shared#^_" "$plist" 2>/dev/null || true
"$plistbuddy" -c "Delete :SchemeUserState:BubuTimeMachineTests.xcscheme_^#shared#^_" "$plist" 2>/dev/null || true
"$plistbuddy" -c "Delete :SuppressBuildableAutocreation" "$plist" 2>/dev/null || true
"$plistbuddy" -c "Add :SuppressBuildableAutocreation dict" "$plist"

for target in BubuWidgetsExtension BubuTimeMachineTests; do
  uuid="$(target_uuid "$target")"
  [[ -n "$uuid" ]] || continue
  "$plistbuddy" -c "Add :SuppressBuildableAutocreation:$uuid dict" "$plist"
  "$plistbuddy" -c "Add :SuppressBuildableAutocreation:$uuid:primary bool true" "$plist"
done
