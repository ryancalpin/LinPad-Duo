#!/bin/bash
# Builds LinPad Duo as an IPA. Used by .github/workflows/duo-ipa.yml and codemagic.yaml;
# runs on any Apple-silicon Mac with Xcode.
#
#   release/duo-build-ipa.sh              -> build-duo/LinPad-Duo.ipa
#
# Two kinds of IPA:
# * Signed (a paid Apple Developer account): with ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (an
#   App Store Connect API key, Admin) and APPLE_TEAM_ID set, Xcode signs it for development
#   with your team, for every device registered in your account. It installs straight from
#   Safari (build-duo/site has the install page and manifest) and lasts a year. Development
#   signing keeps get-task-allow, which fast mode (StikDebug) needs.
# * Otherwise: ad-hoc signed, for SideStore, AltStore, Sideloadly or iloader to re-sign
#   with a free Apple ID.
#
# Env: ROOTFS_URL / ROOTFS_VERSION / ROOTFS_SHA256 (the Linux system to put inside; default:
# LinPad 1.5.0's published one), OUT (the IPA's path), IPA_URL (where the signed IPA will be
# downloaded from, for the install manifest), DUO_ENTITLEMENTS (signed builds; default the
# more-memory entitlements, falling back to the plain ones if the account can't have them).
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

say "GPU libraries (virglrenderer, MoltenVK)"
if [ -f gpu/prefix-ios/lib/libvirglrenderer.a ] && [ -f gpu/prefix-ios/lib/libMoltenVK.a ]; then
    echo "already built"
else
    gpu/build-third-party.sh ios
fi

BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
VERSION=$(sed -n 's/^MARKETING_VERSION = //p' app/AppARM64.xcconfig)
COMMON=(-skipMacroValidation -project iSH.xcodeproj -scheme iSH-ARM64 -configuration Release
        -destination generic/platform=iOS IPHONEOS_DEPLOYMENT_TARGET=16.0
        ISH_JIT_BUILD=enabled ISH_VIRTGPU=enabled CURRENT_PROJECT_VERSION="$BUILD_NUMBER")

if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_P8:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    say "App (Release, signed for development with your team)"
    KEY=$WORK/AuthKey.p8
    (umask 077 && printf '%s\n' "$ASC_KEY_P8" > "$KEY")
    trap 'rm -f "$KEY"' EXIT
    AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY"
          -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
    ARCHIVE=$WORK/LinPad-Duo.xcarchive
    archive() {
        rm -rf "$ARCHIVE"
        # The Linux system goes in through the "Download Root" build phase, before signing.
        xcodebuild archive "${COMMON[@]}" -archivePath "$ARCHIVE" SYMROOT="$WORK/products" \
            DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
            CODE_SIGN_ENTITLEMENTS="$1" LINPAD_ROOTFS="$ROOTFS" "${AUTH[@]}"
    }
    ENTITLEMENTS=${DUO_ENTITLEMENTS:-app/iSH-MoreMemory.entitlements}
    if ! archive "$ENTITLEMENTS"; then
        [ "$ENTITLEMENTS" != app/iSH.entitlements ] || exit 1
        echo "Signing with $ENTITLEMENTS failed; trying again without the extra-memory entitlement." >&2
        archive app/iSH.entitlements
    fi
    cat > "$WORK/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>debugging</string>
	<key>teamID</key><string>$APPLE_TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
PLIST
    rm -rf "$WORK/export"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/export.plist" \
        -exportPath "$WORK/export" "${AUTH[@]}"
    rm -f "$OUT"
    mv "$WORK/export/"*.ipa "$OUT"

    say "Install page"
    SITE=$WORK/site
    rm -rf "$SITE" && mkdir -p "$SITE"
    IPA_URL=${IPA_URL:-https://example.invalid/LinPad-Duo.ipa}
    sed -e "s|@IPA_URL@|$IPA_URL|" -e "s|@BUNDLE_ID@|$BUNDLE_ID|" -e "s|@VERSION@|$VERSION|" \
        release/duo-install/manifest.plist > "$SITE/manifest.plist"
    sed -e "s|@VERSION@|$VERSION ($BUILD_NUMBER)|" -e "s|@COMMIT@|$(git rev-parse --short HEAD)|" \
        release/duo-install/index.html > "$SITE/index.html"
    ls -lh "$OUT"
    exit 0
fi

say "App (unsigned Release build, native JIT, virtgpu)"
xcodebuild "${COMMON[@]}" SYMROOT="$WORK/products" \
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
