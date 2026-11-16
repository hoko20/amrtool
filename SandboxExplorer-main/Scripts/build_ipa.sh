#!/usr/bin/env bash
# SandboxExplorer IPA builder (runs on a macOS GitHub Actions runner or a local Mac).
#
# SIGN_MODE (entitlements are written into the Mach-O code signature, not into
# a loose file -- only a signed binary can carry them):
#
#   unsigned  no code signature at all. Re-sign locally with Sideloadly /
#             AltStore / iOS App Signer; feed it dist/SandboxExplorer.entitlements.plist.
#             Output: SandboxExplorer-unsigned.ipa
#
#   adhoc     ad-hoc signature (-s -) WITH the App Group entitlements embedded.
#             Needs NO certificate and NO secrets. Also emits an unsigned IPA.
#             Stock iOS still requires a normal re-sign, but the entitlements are
#             already inside the binary, so sideload tools inherit them without
#             any manual XML merging. TrollStore / jailbroken devices can install
#             the ad-hoc IPA as-is.
#             Output: SandboxExplorer-unsigned.ipa + SandboxExplorer-adhoc.ipa
#
#   signed    real Apple Development signature via CI secrets -> installable IPA.
#             This is the "build it and just install it" path, no re-sign at all.
#             Output: SandboxExplorer-signed.ipa
#
# Environment:
#   SIGN_MODE, BUNDLE_ID, APP_GROUP_ID, DISPLAY_NAME, CONFIGURATION
#   signed: IOS_P12_BASE64, IOS_P12_PASSWORD, IOS_PROVISION_PROFILE_BASE64,
#           IOS_TEAM_ID, KEYCHAIN_PASSWORD (optional), RUNNER_TEMP (optional)
#
# Outputs (dist/):
#   SandboxExplorer-<mode>.ipa
#   SandboxExplorer.entitlements.plist
#   SandboxExplorer.embedded-entitlements.plist   <- exactly what codesign wrote
#   build-report.txt, xcodebuild.log

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SIGN_MODE="${SIGN_MODE:-unsigned}"
BUNDLE_ID="${BUNDLE_ID:-dev.local.SandboxExplorer}"
APP_GROUP_ID="${APP_GROUP_ID:-group.dev.local.SandboxExplorer}"
DISPLAY_NAME="${DISPLAY_NAME:-SandboxExplorer}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="$ROOT/build/DerivedData"
OUT="$ROOT/dist"
RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
ENT="$ROOT/Config/SandboxExplorer.entitlements"

case "$SIGN_MODE" in
    unsigned|adhoc|signed) ;;
    *) echo "build_ipa.sh: unknown SIGN_MODE '$SIGN_MODE' (use unsigned|adhoc|signed)" >&2; exit 2 ;;
esac

echo "==> configure identities"
bash "$ROOT/Scripts/configure.sh" \
    --bundle-id "$BUNDLE_ID" \
    --app-group "$APP_GROUP_ID" \
    --display-name "$DISPLAY_NAME"

mkdir -p "$OUT" "$DERIVED_DATA"

PROFILE_UUID=""
PROFILE_APP_GROUP_OK="n/a"
if [[ "$SIGN_MODE" == "signed" ]]; then
    for required in IOS_P12_BASE64 IOS_P12_PASSWORD IOS_PROVISION_PROFILE_BASE64 IOS_TEAM_ID; do
        if [[ -z "${!required:-}" ]]; then
            echo "build_ipa.sh: signed mode requires secret $required" >&2
            exit 1
        fi
    done
    KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(uuidgen)}"
    KEYCHAIN="$RUNNER_TEMP/sandboxexplorer-build.keychain-db"

    echo "==> import signing identity"
    python3 -c 'import base64,os,sys; open(sys.argv[1],"wb").write(base64.b64decode(os.environ["IOS_P12_BASE64"]))' \
        "$RUNNER_TEMP/cert.p12"
    python3 -c 'import base64,os,sys; open(sys.argv[1],"wb").write(base64.b64decode(os.environ["IOS_PROVISION_PROFILE_BASE64"]))' \
        "$RUNNER_TEMP/profile.mobileprovision"

    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" \
        -P "$IOS_P12_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
    security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

    security cms -D -i "$RUNNER_TEMP/profile.mobileprovision" > "$RUNNER_TEMP/profile.plist"
    PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$RUNNER_TEMP/profile.plist")"
    PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$PROFILE_DIR"
    cp "$RUNNER_TEMP/profile.mobileprovision" "$PROFILE_DIR/$PROFILE_UUID.mobileprovision"
    echo "    provisioning profile UUID: $PROFILE_UUID"

    # Fail early if the profile does not authorise the App Group. Xcode will
    # happily produce an IPA whose signature silently drops the entitlement.
    if /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups' \
            "$RUNNER_TEMP/profile.plist" 2>/dev/null | grep -Fqx "$APP_GROUP_ID"; then
        PROFILE_APP_GROUP_OK="yes"
    else
        PROFILE_APP_GROUP_OK="NO"
        echo "build_ipa.sh: ERROR provisioning profile does not authorise '$APP_GROUP_ID'." >&2
        echo "    Enable the App Groups capability for this App ID at developer.apple.com," >&2
        echo "    add this exact group, regenerate the profile and update the secret." >&2
        exit 1
    fi
    echo "    profile authorises app group: $PROFILE_APP_GROUP_OK"
fi

echo "==> xcodebuild ($CONFIGURATION, iphoneos, $SIGN_MODE)"
COMMON=(
    -project "$ROOT/SandboxExplorer.xcodeproj"
    -scheme SandboxExplorer
    -configuration "$CONFIGURATION"
    -sdk iphoneos
    -destination 'generic/platform=iOS'
    -derivedDataPath "$DERIVED_DATA"
    ONLY_ACTIVE_ARCH=NO
    APP_BUNDLE_ID="$BUNDLE_ID"
    APP_GROUP_ID="$APP_GROUP_ID"
    APP_DISPLAY_NAME="$DISPLAY_NAME"
    CODE_SIGN_ENTITLEMENTS="Config/SandboxExplorer.entitlements"
)

if [[ "$SIGN_MODE" == "signed" ]]; then
    xcodebuild "${COMMON[@]}" \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGNING_REQUIRED=YES \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="Apple Development" \
        DEVELOPMENT_TEAM="$IOS_TEAM_ID" \
        PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" \
        build 2>&1 | tee "$OUT/xcodebuild.log"
else
    # unsigned AND adhoc build an unmodified, unsigned .app first; adhoc signs
    # a COPY afterwards so the unsigned IPA stays clean.
    xcodebuild "${COMMON[@]}" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGN_STYLE=Manual \
        build 2>&1 | tee "$OUT/xcodebuild.log"
fi

APP="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/SandboxExplorer.app"
if [[ ! -d "$APP" ]]; then
    echo "build_ipa.sh: expected product not found at $APP" >&2
    exit 1
fi

echo "==> verify built bundle"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :WQAppGroupIdentifier' "$APP/Info.plist"

package_ipa() {
    local label="$1" app="$2" stage
    stage="$ROOT/build/ipa-stage-$label"
    rm -rf "$stage"
    mkdir -p "$stage/Payload"
    cp -R "$app" "$stage/Payload/"
    local ipa="$OUT/SandboxExplorer-$label.ipa"
    rm -f "$ipa"
    # -y preserves symlinks; -r recurses; -q quiet.
    (cd "$stage" && zip -qry "$ipa" Payload)
    unzip -t "$ipa" >/dev/null
    unzip -l "$ipa" | grep -q "Payload/SandboxExplorer.app/Info.plist"
    echo "    packaged $ipa ($(stat -f%z "$ipa") bytes)"
}

dump_embedded_entitlements() {
    # codesign -d --entitlements :- prints the XML plist on stdout for a signed
    # binary; unsigned binaries return non-zero and print nothing.
    codesign -d --entitlements :- "$1" 2>/dev/null || true
}

if [[ "$SIGN_MODE" == "unsigned" ]]; then
    echo "==> package unsigned IPA (no signature, entitlements live in the plist file)"
    package_ipa unsigned "$APP"
    EMBEDDED_STATUS="absent (unsigned by design; use dist/SandboxExplorer.entitlements.plist when re-signing)"
    : > "$OUT/SandboxExplorer.embedded-entitlements.plist"

elif [[ "$SIGN_MODE" == "adhoc" ]]; then
    echo "==> package unsigned IPA"
    package_ipa unsigned "$APP"

    echo "==> ad-hoc sign a copy WITH entitlements embedded"
    ADHOC_STAGE="$ROOT/build/adhoc-app"
    rm -rf "$ADHOC_STAGE"
    mkdir -p "$ADHOC_STAGE"
    cp -R "$APP" "$ADHOC_STAGE/SandboxExplorer.app"
    ADHOC_APP="$ADHOC_STAGE/SandboxExplorer.app"
    codesign --force --sign - --entitlements "$ENT" --timestamp=none "$ADHOC_APP"
    codesign -dvv "$ADHOC_APP" 2>&1 | head -n 8 || true
    EMBEDDED="$(dump_embedded_entitlements "$ADHOC_APP")"
    if ! grep -Fq "$APP_GROUP_ID" <<<"$EMBEDDED"; then
        echo "build_ipa.sh: ERROR ad-hoc signature did not embed app group '$APP_GROUP_ID'" >&2
        exit 1
    fi
    printf '%s\n' "$EMBEDDED" > "$OUT/SandboxExplorer.embedded-entitlements.plist"
    echo "    embedded entitlements verified: $APP_GROUP_ID"
    package_ipa adhoc "$ADHOC_APP"
    EMBEDDED_STATUS="present (ad-hoc signature, app group $APP_GROUP_ID)"

else # signed
    echo "==> verify signed bundle"
    codesign -dvv "$APP" 2>&1 | head -n 12
    EMBEDDED="$(dump_embedded_entitlements "$APP")"
    if ! grep -Fq "$APP_GROUP_ID" <<<"$EMBEDDED"; then
        echo "build_ipa.sh: ERROR signed app is missing '$APP_GROUP_ID' in its entitlements." >&2
        echo "    The provisioning profile must enable this App Group." >&2
        exit 1
    fi
    printf '%s\n' "$EMBEDDED" > "$OUT/SandboxExplorer.embedded-entitlements.plist"
    echo "    embedded entitlements verified: $APP_GROUP_ID"
    package_ipa signed "$APP"
    EMBEDDED_STATUS="present (Apple Development signature, app group $APP_GROUP_ID)"
fi

cp "$ENT" "$OUT/SandboxExplorer.entitlements.plist"

echo "==> build report"
{
    echo "SandboxExplorer build report"
    echo "generated          : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "runner              : $(sw_vers -productVersion)"
    echo "xcode               : $(xcodebuild -version | tr '\n' ' ')"
    echo "iphoneos SDK        : $(xcrun --sdk iphoneos --show-sdk-version)"
    echo "configuration       : $CONFIGURATION"
    echo "sign mode           : $SIGN_MODE"
    echo "bundle id           : $BUNDLE_ID"
    echo "app group           : $APP_GROUP_ID"
    echo "display name        : $DISPLAY_NAME"
    echo "profile authorises  : $PROFILE_APP_GROUP_OK"
    echo "provision uuid      : ${PROFILE_UUID:-n/a}"
    echo "embedded app group  : $EMBEDDED_STATUS"
    for ipa in "$OUT"/SandboxExplorer-*.ipa; do
        [[ -f "$ipa" ]] || continue
        echo "ipa                 : $ipa"
        echo "ipa bytes           : $(stat -f%z "$ipa")"
        echo "ipa sha256          : $(shasum -a 256 "$ipa" | awk '{print $1}')"
    done
} > "$OUT/build-report.txt"

cat "$OUT/build-report.txt"
echo "==> done"
