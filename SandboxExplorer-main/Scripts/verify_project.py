#!/usr/bin/env python3
"""Static validation of the SandboxExplorer Xcode project.

Runs on Windows/macOS/Linux without Xcode. It catches the failures that would
otherwise only appear halfway through a GitHub Actions build:
  - broken 24-character object ids or dangling references in project.pbxproj
  - source files listed in the project but missing on disk (and vice versa)
  - mismatched bundle id / app group / Info.plist / entitlements / scheme
  - missing workflow or build scripts
"""

from __future__ import annotations

import os
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "SandboxExplorer.xcodeproj" / "project.pbxproj"
SCHEME = ROOT / "SandboxExplorer.xcodeproj" / "xcshareddata" / "xcschemes" / "SandboxExplorer.xcscheme"
XCCONFIG = ROOT / "Config" / "Project.xcconfig"
ENTITLEMENTS = ROOT / "Config" / "SandboxExplorer.entitlements"
INFOPLIST = ROOT / "Config" / "Info.plist"
WORKFLOW = ROOT / ".github" / "workflows" / "build-ipa.yml"
SOURCES = ROOT / "Sources"

ID_RE = re.compile(r"\b([0-9A-F]{24})\b")
DEF_RE = re.compile(r"^\s*([0-9A-F]{24})\b[^\n]*?=\s*\{", re.M)
BUILD_FILE_RE = re.compile(r"^\s*([0-9A-F]{24})\s*/\* .*? in Sources \*/\s*=\s*\{isa = PBXBuildFile;", re.M)

errors: list[str] = []
checks = 0


def check(condition: bool, message: str) -> None:
    global checks
    checks += 1
    if not condition:
        errors.append(message)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def xcconfig_value(text: str, key: str) -> str:
    match = re.search(r"^\s*" + re.escape(key) + r"\s*=\s*(.+?)\s*$", text, re.M)
    return match.group(1).strip() if match else ""


def main() -> int:
    for path in (PBXPROJ, SCHEME, XCCONFIG, ENTITLEMENTS, INFOPLIST, WORKFLOW, SOURCES):
        check(path.exists(), f"missing: {path}")

    pbx = read(PBXPROJ)
    tokens = set(ID_RE.findall(pbx))
    definitions = set(DEF_RE.findall(pbx))
    dangling = tokens - definitions
    check(not dangling, f"pbxproj references undefined object ids: {sorted(dangling)}")
    check(len(definitions) >= 40, f"pbxproj looks truncated ({len(definitions)} objects)")

    # OpenStep-plist structural sanity: braces, semicolons, object count.
    structural = pbx
    structural = re.sub(r"/\*.*?\*/", "", structural, flags=re.S)
    structural = re.sub(r"//[^\n]*", "", structural)
    structural = re.sub(r'"(?:\\.|[^"\\])*"', '""', structural)
    check(structural.count("{") == structural.count("}"),
          f"pbxproj braces unbalanced ({structural.count('{')} vs {structural.count('}')})")
    check(pbx.count("isa = ") >= 40, "pbxproj is missing object definitions")
    for required_section in ("PBXBuildFile", "PBXFileReference", "PBXGroup",
                             "PBXNativeTarget", "PBXProject", "PBXSourcesBuildPhase",
                             "XCBuildConfiguration", "XCConfigurationList"):
        check(f"/* Begin {required_section} section */" in pbx,
              f"pbxproj missing {required_section} section")

    # Every source file on disk must be listed in the project and in Sources.
    disk_sources = sorted(p.name for p in SOURCES.glob("*.m"))
    listed_sources = sorted(set(re.findall(r"path = ([\w-]+\.m);", pbx)))
    check(disk_sources == listed_sources,
          f"source list mismatch: disk={disk_sources} pbxproj={listed_sources}")

    sources_phase = re.search(
        r"/\* Begin PBXSourcesBuildPhase section \*/(.*?)/\* End PBXSourcesBuildPhase section \*/",
        pbx, re.S)
    check(sources_phase is not None, "PBXSourcesBuildPhase section not found")
    if sources_phase:
        build_files = re.findall(r"^\s*([0-9A-F]{24})\s*/\* .*? in Sources \*/,",
                                 sources_phase.group(1), re.M)
        check(len(build_files) == len(disk_sources),
              f"Sources build phase has {len(build_files)} entries, expected {len(disk_sources)}")

    # Headers referenced in WQKit.h / WQUI.h must exist.
    for header in ("WQKit.h", "WQUI.h"):
        check((SOURCES / header).exists(), f"missing header {header}")
        check(f"path = {header};" in pbx, f"{header} not listed in pbxproj")

    # Scheme must point at the native target id.
    target_ids = re.findall(
        r"^\s*([0-9A-F]{24})[^\n]*?=\s*\{\s*isa = PBXNativeTarget;", pbx, re.M)
    check(len(target_ids) == 1, f"expected exactly one native target, found {target_ids}")
    if target_ids:
        check(target_ids[0] in read(SCHEME),
              "scheme BlueprintIdentifier does not match the native target id")

    # Build settings / plist consistency.
    xcconfig = read(XCCONFIG)
    bundle_id = xcconfig_value(xcconfig, "APP_BUNDLE_ID")
    group_id = xcconfig_value(xcconfig, "APP_GROUP_ID")
    check(bool(re.match(r"^[A-Za-z0-9.-]+$", bundle_id)), f"invalid APP_BUNDLE_ID: {bundle_id!r}")
    check(bool(re.match(r"^[A-Za-z0-9.-]+$", group_id)), f"invalid APP_GROUP_ID: {group_id!r}")

    with open(ENTITLEMENTS, "rb") as fh:
        ent = plistlib.load(fh)
    groups = ent.get("com.apple.security.application-groups", [])
    check(groups == [group_id], f"entitlements group {groups} != xcconfig {group_id!r}")

    with open(INFOPLIST, "rb") as fh:
        info = plistlib.load(fh)
    check(info.get("WQAppGroupIdentifier") == group_id,
          "Info.plist WQAppGroupIdentifier does not match xcconfig")
    manifest = info.get("UIApplicationSceneManifest", {})
    scene_configs = manifest.get("UISceneConfigurations", {})
    scene_entry = scene_configs.get("UIWindowSceneSessionRoleApplication", [{}])[0]
    check(scene_entry.get("UISceneDelegateClassName") == "WQSceneDelegate",
          "Info.plist scene delegate class must be WQSceneDelegate")
    check(info.get("UIFileSharingEnabled") is True, "UIFileSharingEnabled must be YES for exports")

    check("CODE_SIGN_ENTITLEMENTS = Config/SandboxExplorer.entitlements;" in pbx,
          "target does not reference the entitlements file")
    check("INFOPLIST_FILE = Config/Info.plist;" in pbx,
          "target does not reference Info.plist")
    check("GENERATE_INFOPLIST_FILE = NO;" in pbx,
          "GENERATE_INFOPLIST_FILE must be NO (we ship our own Info.plist)")

    workflow = read(WORKFLOW)
    check("runs-on: macos-26" in workflow, "workflow must run on a macOS 26 image")
    check("Scripts/build_ipa.sh" in workflow, "workflow must call the IPA builder")
    check("actions/upload-artifact@v4" in workflow, "workflow must upload the IPA artifact")

    builder = read(ROOT / "Scripts" / "build_ipa.sh")
    # The three signing modes must stay in sync between the workflow choices,
    # the builder's dispatch case, and the helper CLIs. A mismatch silently
    # produces an unsigned IPA when the user asked for embedded entitlements.
    expected_modes = {"unsigned", "adhoc", "signed"}
    workflow_modes = set(re.findall(r"^\s+-\s+(unsigned|adhoc|signed)\s*$", workflow, re.M))
    check(workflow_modes == expected_modes,
          f"workflow sign_mode choices must be {sorted(expected_modes)}, got {sorted(workflow_modes)}")
    check(all(re.search(rf"\b{re.escape(mode)}\b", builder) for mode in expected_modes),
          "build_ipa.sh must implement all three signing modes")
    check('CODE_SIGN_ENTITLEMENTS="Config/SandboxExplorer.entitlements"' in builder,
          "builder must pass CODE_SIGN_ENTITLEMENTS so scoped entitlements land in the signature")
    check("codesign --force --sign - --entitlements" in builder,
          "adhoc mode must embed entitlements with an ad-hoc codesign")
    check("setup_signing_secrets.ps1" in read(ROOT / ".gitignore")
          or "Scripts/.secrets/" in read(ROOT / ".gitignore"),
          ".gitignore must exclude locally generated secret payloads")
    for cli, pattern in (("github_build.py", r'"adhoc", "unsigned", "signed"'),
                         ("push_to_github.ps1", r'"adhoc", "unsigned", "signed"')):
        check(re.search(pattern, read(ROOT / "Scripts" / cli)) is not None,
              f"{cli} must accept all three signing modes")

    for script in ("configure.sh", "build_ipa.sh", "verify_project.py", "github_build.py"):
        check((ROOT / "Scripts" / script).exists(), f"missing script Scripts/{script}")

    # Every public function declared in WQKit.h should have an implementation
    # somewhere in the .m files (a cheap but useful sanity check).
    kit = read(SOURCES / "WQKit.h")
    all_impl = "\n".join(read(p) for p in SOURCES.glob("*.m"))
    declared = set(re.findall(r"^(?:[A-Za-z_][\w <>*,]*?)\b(WQ[A-Za-z]+)\s*\(", kit, re.M))
    missing = sorted(name for name in declared if f"{name}(" not in all_impl)
    check(not missing, f"declared but not implemented: {missing}")

    # Clang rejects C arrays captured by a block and rejects invented priority
    # constants. Both mistakes only show up on a real macOS runner, so catch
    # them here before spending an Actions build.
    valid_priorities = {
        "DISPATCH_QUEUE_PRIORITY_HIGH",
        "DISPATCH_QUEUE_PRIORITY_DEFAULT",
        "DISPATCH_QUEUE_PRIORITY_LOW",
        "DISPATCH_QUEUE_PRIORITY_BACKGROUND",
    }
    used_priorities = set(re.findall(r"\b(DISPATCH_QUEUE_PRIORITY_[A-Z_]+)\b", all_impl))
    check(not (used_priorities - valid_priorities),
          f"invalid dispatch priority constants: {sorted(used_priorities - valid_priorities)}")

    array_decl = re.compile(
        r"\b(?:char|uint8_t|unsigned char|int|uint64_t|size_t)\s+(\w+)\s*\[")
    for src in sorted(SOURCES.glob("*.m")):
        text = read(src)
        if "dispatch_apply" not in text:
            continue
        head, body = text.split("dispatch_apply", 1)
        captured = [name for name in array_decl.findall(head)
                    if re.search(r"\b" + re.escape(name) + r"\b", body)]
        check(not captured,
              f"{src.name}: C array(s) {captured} captured by a block; use heap allocation")

    print(f"verify_project: {checks} checks")
    if errors:
        for error in errors:
            print("  FAIL  " + error)
        print(f"verify_project: {len(errors)} problem(s)")
        return 1
    print("verify_project: PASS")
    print(f"  bundle id : {bundle_id}")
    print(f"  app group : {group_id}")
    print(f"  sources   : {len(disk_sources)} .m files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
