#!/bin/sh
# Archives a Release build and uploads it to App Store Connect for TestFlight.
#
#   scripts/testflight.sh <build-number>
#
# Needs Config/Local.xcconfig (team + iCloud settings) and Xcode signed in to
# the developer account. Each upload needs a build number higher than the last.
set -eu
cd "$(dirname "$0")/.."

BUILD="${1:?usage: scripts/testflight.sh <build-number>}"
TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig)
[ -n "$TEAM" ] || { echo "Set DEVELOPMENT_TEAM in Config/Local.xcconfig" >&2; exit 1; }

ARCHIVE=.build/archive/LittleBabyLog.xcarchive
EXPORT=.build/export
mkdir -p "$EXPORT"
cat > "$EXPORT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

xcodegen generate -q
rm -rf "$ARCHIVE"
xcodebuild -project LittleBabyLog.xcodeproj -scheme LittleBabyLog -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD" archive
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT/ExportOptions.plist" \
  -exportPath "$EXPORT" -allowProvisioningUpdates
