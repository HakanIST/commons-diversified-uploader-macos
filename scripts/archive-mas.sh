#!/bin/sh
# Archives a Release build and exports a signed Mac App Store package.
#
# Requires ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID (App Store Connect API
# key) in the environment. Pass "upload" to send the package to App Store
# Connect instead of only writing it to build-mas/export.
set -eu
cd "$(dirname "$0")/.."
destination="${1:-export}"
key_path=$(eval echo "$ASC_KEY_PATH")
auth="-allowProvisioningUpdates -authenticationKeyPath $key_path -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID"

xcodegen generate
# shellcheck disable=SC2086
xcodebuild -project CommonsDiversifiedUploader.xcodeproj \
  -scheme CommonsDiversifiedUploader -configuration Release \
  -derivedDataPath build-mas -archivePath build-mas/App.xcarchive \
  $auth archive

team=$(xcodebuild -project CommonsDiversifiedUploader.xcodeproj -showBuildSettings 2>/dev/null | awk '/ DEVELOPMENT_TEAM = /{print $3; exit}')
cat > build-mas/export.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>$destination</string>
<key>teamID</key><string>$team</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
rm -rf build-mas/export
# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath build-mas/App.xcarchive \
  -exportPath build-mas/export -exportOptionsPlist build-mas/export.plist $auth
