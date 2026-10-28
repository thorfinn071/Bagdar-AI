#!/bin/bash
# Run locally on the Mac with a connected, trusted iPhone. No camera collection
# is started by these unit tests. Keep the xcresult and log as device evidence.
set -euo pipefail
if [ "$#" -ne 3 ]; then
  echo "Usage: bash verify_on_mac.sh TEAM_ID IPHONE_UDID NEW_OUTPUT_DIRECTORY" >&2
  exit 64
fi
task_team="$1"
task_device="$2"
task_output="$3"
task_root="$(cd "$(dirname "$0")" && pwd)"
if [ -e "$task_output" ]; then
  echo "Choose a new output directory; existing verification is preserved." >&2
  exit 1
fi
mkdir -p "$task_output"
xcodebuild -version > "$task_output/xcode-version.txt"
(
  cd "$task_root"
  find BagdarCapture BagdarCaptureTests BagdarCapture.xcodeproj -type f \
    \( -name '*.swift' -o -name '*.plist' -o -name '*.pbxproj' -o -name '*.xcscheme' \) \
    -print | LC_ALL=C sort | while IFS= read -r task_file; do shasum -a 256 "$task_file"; done
) > "$task_output/source-sha256.txt"
task_source_id="$(shasum -a 256 "$task_output/source-sha256.txt" | cut -d ' ' -f 1)"
echo "$task_source_id" > "$task_output/recorder-source-id.txt"
xcodebuild -project "$task_root/BagdarCapture.xcodeproj" -scheme BagdarCapture \
  -destination "id=$task_device" -configuration Debug \
  "DEVELOPMENT_TEAM=$task_team" "BAGDAR_CAPTURE_SOURCE_ID=$task_source_id" -allowProvisioningUpdates \
  -resultBundlePath "$task_output/BagdarCapture.xcresult" test \
  2>&1 | tee "$task_output/xcode-test.log"
echo "Native compilation/unit checks finished. Manual camera/lifecycle checks remain separate."
