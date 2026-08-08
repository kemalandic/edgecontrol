#!/bin/bash
#
# Builds a signed, notarised EdgeControl.dmg.
#
# Needs a Developer ID Application certificate in the login keychain and a
# notarytool keychain profile. Create the profile once with:
#
#   xcrun notarytool store-credentials edgecontrol \
#       --apple-id you@example.com --team-id YOURTEAMID --password <app-specific-password>
#
# Override the defaults through the environment if yours differ:
#
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=myprofile ./Scripts/package.sh
#
set -euo pipefail

TEAM_ID="${TEAM_ID:-CNRZ47Y629}"
NOTARY_PROFILE="${NOTARY_PROFILE:-edgecontrol}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
APP="$BUILD/export/EdgeControl.app"
DMG="$BUILD/EdgeControl.dmg"
STAGE="$BUILD/dmg"

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
BUILD_NUMBER=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml)
[ -n "$VERSION" ] || { echo "could not read MARKETING_VERSION from project.yml" >&2; exit 1; }

echo "==> EdgeControl $VERSION ($BUILD_NUMBER)"

# Resolved before the archive rather than after it: a missing certificate should
# cost a second, not a full Release build.
IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -v team="($TEAM_ID)" '/Developer ID Application/ && index($0, team) { print; exit }' \
    | sed -n 's/.*"\(.*\)".*/\1/p')}"
if [ -z "$IDENTITY" ]; then
    echo "No 'Developer ID Application' certificate for team $TEAM_ID in the keychain." >&2
    echo "Set IDENTITY= to name one explicitly, or TEAM_ID= if yours differs." >&2
    exit 1
fi
echo "    signing as: $IDENTITY"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "==> Regenerating the Xcode project"
xcodegen generate

echo "==> Archiving"
xcodebuild archive \
    -project EdgeControl.xcodeproj \
    -scheme EdgeControl \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$BUILD/EdgeControl.xcarchive" \
    -quiet

# Developer ID rather than App Store: this ships outside the store, and the
# widget extension has to be re-signed with the same identity, which
# exportArchive handles for us.
cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Exporting"
xcodebuild -exportArchive \
    -archivePath "$BUILD/EdgeControl.xcarchive" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist" \
    -exportPath "$BUILD/export" \
    -quiet

if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo "==> Skipping notarisation (SKIP_NOTARIZE=1)"
else
    # The app is notarised and stapled BEFORE it goes in the image. Stapling
    # only the disk image leaves the copy the user drags to /Applications
    # without a ticket, so its first launch needs Apple reachable — which is
    # exactly when a fresh install is least likely to be online.
    echo "==> Notarising the app"
    ditto -c -k --keepParent "$APP" "$BUILD/EdgeControl.zip"
    xcrun notarytool submit "$BUILD/EdgeControl.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
fi

echo "==> Staging the disk image"
# A symlink to /Applications is what makes the window a drag-and-drop install
# rather than something the user has to file away themselves.
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "EdgeControl" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

echo "==> Signing the disk image"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

if [ "$SKIP_NOTARIZE" != "1" ]; then
    # The image needs its own ticket too, so Gatekeeper can clear it at
    # download time without unpacking anything.
    echo "==> Notarising the disk image"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "==> Verifying"
# What Gatekeeper will decide on the user's machine, asked before we ship
# rather than after someone reports the app will not open.
spctl --assess --type open --context context:primary-signature -vv "$DMG"
codesign --verify --deep --strict --verbose=2 "$APP"
if [ "$SKIP_NOTARIZE" != "1" ]; then
    # Both tickets, checked separately: the image's clears the download, the
    # app's is the one that survives being dragged to /Applications.
    xcrun stapler validate "$DMG"
    xcrun stapler validate "$APP"
fi

echo
echo "Built $DMG"
ls -lh "$DMG" | awk '{print "  " $5, $9}'
