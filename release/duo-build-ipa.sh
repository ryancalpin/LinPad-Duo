#!/bin/bash
# Builds LinPad Duo as an IPA that SideStore, AltStore, Sideloadly or iloader re-sign with
# your own Apple ID, so it installs from any computer (an Intel Mac included) with a free
# account. Used by codemagic.yaml; runs on any Apple-silicon Mac with Xcode 27.
#
#   release/duo-build-ipa.sh              -> build-duo/LinPad-Duo.ipa
#
# Env: ROOTFS_URL / ROOTFS_VERSION (the Linux system to put inside; default: LinPad 1.5.0's
# published one), OUT (the IPA's path).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
WORK=$ROOT/build-duo
OUT=${OUT:-$WORK/LinPad-Duo.ipa}
ROOTFS_URL=${ROOTFS_URL:-https://github.com/fspecii/LinPad/releases/download/v1.5.0/linpad-rootfs-1.5.0.tar.gz}
ROOTFS_VERSION=${ROOTFS_VERSION:-202610031701}
ROOTFS_SHA256=${ROOTFS_SHA256:-b5e852cfe2d9763863323895a6f94194ac980b226926a6f6aba27c5f5e41ea9b}
BUNDLE_ID=$(sed -n 's/^ROOT_BUNDLE_IDENTIFIER = //p' app/iSH.xcconfig).arm64
APP_GROUP=group.$BUNDLE_ID
for prefix in /opt/homebrew /usr/local; do
    [ -d "$prefix/opt/llvm/bin" ] && export PATH="$prefix/opt/lld/bin:$prefix/opt/llvm/bin:$PATH"
done
say() { printf '\n==> %s\n' "$*"; }
mkdir -p "$WORK"

say "Xcode"
xcodebuild -version
SDK=$(xcrun --sdk iphoneos --show-sdk-version)
echo "iOS SDK $SDK"
# The Duo hinge APIs came with the iOS 27.1 SDK.
if [ "$(printf '%s\n' "$SDK" 27.1 | sort -V | head -n1)" != 27.1 ]; then
    echo "iOS SDK $SDK is older than 27.1: building without the hinge APIs (closed/open still work)"
    export LINPAD_HINGE_API=0
fi

say "Linux system"
ROOTFS=$WORK/linpad-rootfs.tar.gz
if [ ! -f "$ROOTFS" ]; then
    curl -fL --retry 3 -o "$ROOTFS.part" "$ROOTFS_URL"
    mv "$ROOTFS.part" "$ROOTFS"
fi
echo "$ROOTFS_SHA256  $ROOTFS" | shasum -a 256 -c -
echo "$ROOTFS_VERSION" > "$WORK/linpad-rootfs.version"

say "App (unsigned Release build, native JIT, virtgpu)"
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
xcodebuild -skipMacroValidation -project iSH.xcodeproj -scheme iSH-ARM64 -configuration Release \
    -destination generic/platform=iOS SYMROOT="$WORK/products" IPHONEOS_DEPLOYMENT_TARGET=16.0 \
    ISH_JIT_BUILD=enabled ISH_VIRTGPU=enabled CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= build
APP="$WORK/products/Release-iphoneos/iSH ARM64.app"
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

say "Ad-hoc signature (the sideloading app re-signs it with your Apple ID)"
ENT=$WORK/entitlements
mkdir -p "$ENT"
# The app group, user fonts, and get-task-allow, which StikDebug needs for fast mode.
cat > "$ENT/app.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.user-fonts</key>
	<array><string>app-usage</string></array>
	<key>com.apple.security.application-groups</key>
	<array><string>$APP_GROUP</string></array>
	<key>get-task-allow</key>
	<true/>
</dict>
</plist>
PLIST
sed -e '/user-fonts/,/<\/array>/d' -e '/get-task-allow/,/<true\/>/d' "$ENT/app.plist" > "$ENT/extension.plist"
find "$APP/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -exec codesign --force --sign - {} \; 2>/dev/null || true
for ext in "$APP"/PlugIns/*.appex; do
    [ -d "$ext" ] && codesign --force --sign - --entitlements "$ENT/extension.plist" --generate-entitlement-der "$ext"
done
release/embed-rootfs.sh "$APP" "$ROOTFS"
codesign --force --sign - --entitlements "$ENT/app.plist" --generate-entitlement-der "$APP"
codesign -v --strict --deep "$APP"

say "IPA"
STAGE=$WORK/ipa-stage
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/iSH ARM64.app"
(cd "$STAGE" && zip -qry -X "$OUT" Payload)
rm -rf "$STAGE"
ls -lh "$OUT"
