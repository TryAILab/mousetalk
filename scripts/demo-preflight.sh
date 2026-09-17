#!/bin/zsh
set -u

app="${MOUSETALK_APP:-/Applications/MouseTalk.app}"
expected_version="${MOUSETALK_VERSION:-0.6.0}"
bundle_id="io.github.aaronz021.double-click-mouse"
failures=0

check_equal() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $label = $actual"
  else
    echo "FAIL: $label = $actual (expected $expected)"
    failures=$((failures + 1))
  fi
}

if [[ ! -d "$app" ]]; then
  echo "FAIL: app not found at $app"
  exit 1
fi

display_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app/Contents/Info.plist" 2>/dev/null || echo missing)
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || echo missing)
check_equal "display name" "$display_name" "妙语 MouseTalk"
check_equal "version" "$version" "$expected_version"

if codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
  echo "PASS: code signature is internally valid"
else
  echo "FAIL: code signature verification failed"
  failures=$((failures + 1))
fi

if pgrep -f "^$app/Contents/MacOS/DoubleClickMouse$" >/dev/null; then
  echo "PASS: the selected app is running"
else
  echo "FAIL: the selected app is not running"
  failures=$((failures + 1))
fi

listen=$(defaults read "$bundle_id" diagnosticCanListen 2>/dev/null || echo 0)
accessibility=$(defaults read "$bundle_id" diagnosticAXTrusted 2>/dev/null || echo 0)
monitor=$(defaults read "$bundle_id" diagnosticMonitorRunning 2>/dev/null || echo 0)
check_equal "Input Monitoring" "$listen" "1"
check_equal "Accessibility" "$accessibility" "1"
check_equal "mouse event monitor" "$monitor" "1"

voice_button=$(defaults read "$bundle_id" selectedButton 2>/dev/null || echo unbound)
send_button=$(defaults read "$bundle_id" returnButton 2>/dev/null || echo unbound)
shortcut=$(defaults read "$bundle_id" outputKey 2>/dev/null || echo unset)
mode=$(defaults read "$bundle_id" eventShape 2>/dev/null || echo unset)
echo "INFO: voice button = $voice_button; send button = $send_button; shortcut = $shortcut; mode = $mode"

if [[ "$voice_button" == "unbound" || "$send_button" == "unbound" ]]; then
  echo "FAIL: voice and send buttons must both be bound for the core demo"
  failures=$((failures + 1))
fi
if [[ "$mode" != "keyboard" ]]; then
  echo "WARN: standard mode (keyboard) is preferred for a one-press toggle; rehearse compatibility mode before recording"
fi
if pgrep -if 'logi[[:space:]]*options|logioptions' >/dev/null; then
  echo "WARN: Logi Options+ is running; remove overlapping side-button actions before recording"
fi

if (( failures > 0 )); then
  echo "Preflight failed with $failures blocking item(s)."
  exit 1
fi

echo "Automated preflight passed. Manual mouse + Doubao start/stop/send rehearsal is still required."
