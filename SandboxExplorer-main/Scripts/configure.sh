#!/usr/bin/env bash
# SandboxExplorer identity configuration.
#
# Rewrites Config/Project.xcconfig, Config/SandboxExplorer.entitlements and
# Config/Info.plist so that the bundle id / app group / display name are all
# consistent. Run this BEFORE xcodebuild (the GitHub Actions workflow does it).
#
# Usage:
#   ./Scripts/configure.sh \
#       --bundle-id com.yourname.sandbox \
#       --app-group group.com.yourname.sandbox \
#       --display-name "沙盒管家"
#
# The App Group MUST be present in the provisioning profile used to sign the
# app. Without it containerURLForSecurityApplicationGroupIdentifier: returns
# nil and the worse_query technique cannot issue a token.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCCONFIG="$ROOT/Config/Project.xcconfig"
ENTITLEMENTS="$ROOT/Config/SandboxExplorer.entitlements"
TEMPLATE="$ROOT/Config/SandboxExplorer.entitlements.template"
INFOPLIST="$ROOT/Config/Info.plist"

BUNDLE_ID="${APP_BUNDLE_ID:-dev.local.SandboxExplorer}"
GROUP_ID="${APP_GROUP_ID:-group.dev.local.SandboxExplorer}"
DISPLAY_NAME="${APP_DISPLAY_NAME:-SandboxExplorer}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-id)    BUNDLE_ID="$2"; shift 2 ;;
        --app-group)    GROUP_ID="$2"; shift 2 ;;
        --display-name) DISPLAY_NAME="$2"; shift 2 ;;
        -h|--help)      sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "configure.sh: unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "configure.sh: invalid bundle id: $BUNDLE_ID" >&2; exit 1
fi
if [[ ! "$GROUP_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "configure.sh: invalid app group id: $GROUP_ID" >&2; exit 1
fi

python3 - "$BUNDLE_ID" "$GROUP_ID" "$DISPLAY_NAME" \
        "$XCCONFIG" "$ENTITLEMENTS" "$TEMPLATE" "$INFOPLIST" <<'PY'
import plistlib, re, sys

bundle, group, display, xcconfig, entitlements, template, infoplist = sys.argv[1:]

# 1. xcconfig
with open(xcconfig, "r", encoding="utf-8") as fh:
    text = fh.read()
def replace_key(text, key, value):
    pattern = re.compile(r"^(" + re.escape(key) + r"\s*=\s*).*$", re.M)
    if pattern.search(text):
        return pattern.sub(lambda m: m.group(1) + value, text)
    return text.rstrip() + "\n" + key + " = " + value + "\n"
text = replace_key(text, "APP_BUNDLE_ID", bundle)
text = replace_key(text, "APP_GROUP_ID", group)
text = replace_key(text, "APP_DISPLAY_NAME", display)
with open(xcconfig, "w", encoding="utf-8") as fh:
    fh.write(text)

# 2. entitlements (regenerated from template so the checked-in file never
#    silently keeps a stale group id)
with open(template, "r", encoding="utf-8") as fh:
    ent = fh.read()
ent = ent.replace("__APP_GROUP_ID__", group)
with open(entitlements, "w", encoding="utf-8") as fh:
    fh.write(ent)
plistlib.loads(ent.encode("utf-8"))  # validate

# 3. Info.plist display name
with open(infoplist, "rb") as fh:
    info = plistlib.load(fh)
info["CFBundleDisplayName"] = display
info["WQAppGroupIdentifier"] = group
with open(infoplist, "wb") as fh:
    plistlib.dump(info, fh, sort_keys=False)
PY

echo "configure.sh: bundle id     = $BUNDLE_ID"
echo "configure.sh: app group     = $GROUP_ID"
echo "configure.sh: display name  = $DISPLAY_NAME"
echo "configure.sh: entitlements  = $ENTITLEMENTS"
