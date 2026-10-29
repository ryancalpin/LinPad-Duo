#!/bin/bash
# Installs the app from the last signed build onto the iPhone Duo and opens it. Works over
# the cable or over Wi-Fi: once the phone has been paired with this Mac over USB, it can be
# reached on the same Wi-Fi network while it's unlocked.
#
#   release/duo-install.sh [DEVICE]    DEVICE: a name or UDID (default: the first iPhone Duo)
#
# Build first with release/duo-build-ipa.sh (signed: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH,
# APPLE_TEAM_ID set).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=$ROOT/build-duo/LinPad-Duo.xcarchive/Products/Applications/iSH\ ARM64.app
BUNDLE_ID=$(sed -n 's/^ROOT_BUNDLE_IDENTIFIER = //p' "$ROOT/app/iSH.xcconfig").arm64
[ -d "$APP" ] || { echo "no signed build at $APP; run release/duo-build-ipa.sh first" >&2; exit 1; }

DEVICE=${1:-}
if [ -z "$DEVICE" ]; then
    LIST=$(mktemp)
    trap 'rm -f "$LIST"' EXIT
    xcrun devicectl list devices --json-output "$LIST" >/dev/null
    DEVICE=$(python3 - "$LIST" <<'PY'
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    c = d["connectionProperties"]
    # iPhone19,4 is the iPhone Duo; skip simulators.
    if d["hardwareProperties"].get("productType") == "iPhone19,4" and c.get("transportType") in ("wired", "localNetwork"):
        print(d["hardwareProperties"]["udid"], c["transportType"], file=sys.stderr)
        print(d["hardwareProperties"]["udid"])
        break
PY
)
    [ -n "$DEVICE" ] || { echo "no iPhone Duo found: unlock it, and keep it on the same Wi-Fi as this Mac (or plug it in)" >&2; exit 1; }
fi

xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID"
