#!/usr/bin/env python3
"""Create/refresh the GitHub repo, push, trigger the IPA build and download it.

This is the one-command path for Windows users with no local Xcode:

    set GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
    python Scripts/github_build.py --repo SandboxExplorer

What it does:
  1. creates a private GitHub repository (or reuses an existing one),
  2. commits this working tree and pushes it to main,
  3. waits for the Actions run triggered by the push (falls back to a manual
     workflow_dispatch if the push trigger did not fire),
  4. downloads the artifact and extracts the .ipa into ./dist/.

The token is only sent via an http.extraheader, never written to .git/config
or printed to the console.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://api.github.com"
DIST = ROOT / "dist"


def github_request(method: str, path: str, token: str, payload=None, raw: bool = False):
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "SandboxExplorer-Build/1.0",
    }
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(API + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            body = response.read()
            if raw:
                return response.status, body
            return response.status, json.loads(body or b"{}")
    except urllib.error.HTTPError as error:
        body = error.read()
        try:
            detail = json.loads(body or b"{}")
        except json.JSONDecodeError:
            detail = {"message": body.decode("utf-8", "replace")[:400]}
        return error.code, detail


def run_git(args: list[str]) -> tuple[int, str]:
    process = subprocess.run(["git", "-C", str(ROOT)] + args,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding="utf-8", errors="replace")
    return process.returncode, (process.stdout or "").strip()


def git_config_args(name: str, email: str) -> list[str]:
    return ["-c", f"user.name={name}", "-c", f"user.email={email}"]


def log(message: str) -> None:
    print(f"[github-build] {message}", flush=True)


def token_from_gh_cli() -> str:
    """Reuse the OAuth token cached by `gh auth login` (no manual PAT needed)."""
    for exe in ("gh", "gh.exe"):
        try:
            proc = subprocess.run([exe, "auth", "token"],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True, timeout=20)
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
            continue
        value = (proc.stdout or "").strip()
        if proc.returncode == 0 and value:
            return value
    return ""


def resolve_token(explicit: str) -> str:
    token = (explicit or "").strip()
    if token:
        return token
    token = token_from_gh_cli()
    if token:
        log("using the token from `gh auth token` (GitHub CLI login)")
        return token
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Build SandboxExplorer.ipa with GitHub Actions")
    parser.add_argument("--repo", default="SandboxExplorer", help="GitHub repository name")
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN", ""),
                        help="GitHub token (or set GITHUB_TOKEN)")
    parser.add_argument("--public", action="store_true", help="create a public repo (default: private)")
    parser.add_argument("--no-wait", action="store_true", help="push only, do not poll the run")
    parser.add_argument("--timeout", type=int, default=45, help="minutes to wait for the run")
    parser.add_argument("--bundle-id", default="dev.local.SandboxExplorer")
    parser.add_argument("--app-group", default="group.dev.local.SandboxExplorer")
    parser.add_argument("--display-name", default="沙盒管家")
    parser.add_argument("--sign-mode", choices=["adhoc", "unsigned", "signed"], default="adhoc")
    parser.add_argument("--force-push", action="store_true")
    parser.add_argument("--verify-only", action="store_true", help="run the local validator and exit")
    args = parser.parse_args()

    if args.verify_only:
        return subprocess.call([sys.executable, str(ROOT / "Scripts" / "verify_project.py")])

    args.token = resolve_token(args.token)
    if not args.token:
        log("ERROR: no GitHub credentials. Pick one of these:")
        log("  A) set GITHUB_TOKEN / --token with a classic PAT (scopes: repo + workflow)")
        log("     create it at https://github.com/settings/tokens/new")
        log("  B) install GitHub CLI and run: gh auth login --scopes 'repo,workflow'")
        log("     this script then reads `gh auth token` automatically")
        log("  C) push manually (Git Credential Manager browser login) and download")
        log("     the IPA from the repository's Actions page")
        return 2

    token = args.token.strip()
    status, user = github_request("GET", "/user", token)
    if status != 200 or "login" not in user:
        log(f"ERROR: token validation failed ({status}): {user.get('message', user)}")
        return 2
    owner = user["login"]
    log(f"authenticated as {owner}")

    # 1. Create (or reuse) the repository.
    status, repo = github_request("POST", "/user/repos", token, {
        "name": args.repo,
        "private": not args.public,
        "description": "SandboxExplorer - iOS sandbox / app-container file manager built with GitHub Actions",
        "has_issues": False,
        "has_projects": False,
        "has_wiki": False,
        "auto_init": False,
    })
    if status == 201:
        log(f"created repository https://github.com/{owner}/{args.repo}")
    elif status == 422:
        log(f"repository https://github.com/{owner}/{args.repo} already exists, reusing it")
    else:
        log(f"ERROR: cannot create repository ({status}): {repo.get('message', repo)}")
        return 2

    # 2. Commit the working tree.
    if not (ROOT / ".git").exists():
        code, out = run_git(["init", "-b", "main"])
        log("git init: " + (out or f"exit {code}"))
    run_git(["symbolic-ref", "HEAD", "refs/heads/main"])
    git_cfg = git_config_args("SandboxExplorer Builder", "builder@users.noreply.github.com")
    code, out = run_git(git_cfg + ["add", "-A"])
    if code != 0:
        log(f"ERROR: git add failed: {out}")
        return 2
    code, staged = run_git(["diff", "--cached", "--quiet"])
    if code == 1:
        code, out = run_git(git_cfg + ["commit", "-m", "Build SandboxExplorer IPA from GitHub Actions"])
        if code != 0:
            log(f"ERROR: git commit failed: {out}")
            return 2
        log("committed local changes")
    else:
        log("no local changes to commit")

    # 3. Push. The token lives in a one-shot -c option, never in .git/config.
    push_url = f"https://github.com/{owner}/{args.repo}.git"
    push_args = ["-c", f"http.extraheader=AUTHORIZATION: Bearer {token}", "push"]
    if args.force_push:
        push_args.append("--force")
    push_args += [push_url, "HEAD:refs/heads/main"]
    pushed_at = datetime.now(timezone.utc) - timedelta(seconds=5)
    code, out = run_git(push_args)
    if code != 0:
        log(f"ERROR: git push failed: {out}")
        if "workflow" in out.lower() or "refusing to allow" in out.lower():
            log("       The token lacks the 'workflow' scope (needed to push .yml files).")
            log("       classic PAT: regenerate with workflow checked;")
            log("       GitHub CLI:  gh auth refresh -h github.com -s workflow")
        log("       Try --force-push if the remote has an unrelated history.")
        return 2
    log("pushed to main")

    actions_url = f"https://github.com/{owner}/{args.repo}/actions"
    if args.no_wait:
        log(f"done. Open {actions_url} to watch the build.")
        return 0

    # 4. Find the run created by this push; fall back to workflow_dispatch.
    log("waiting for the workflow run ...")
    run_id = None
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        status, data = github_request("GET", f"/repos/{owner}/{args.repo}/actions/runs?per_page=10", token)
        if status == 200:
            for run in data.get("workflow_runs", []):
                created = datetime.fromisoformat(run["created_at"].replace("Z", "+00:00"))
                if created >= pushed_at and run.get("head_branch") == "main":
                    run_id = run["id"]
                    log(f"found run #{run_id} ({run.get('event')}, {run.get('status')})")
                    break
        if run_id:
            break
        time.sleep(8)

    if not run_id:
        log("push trigger not observed; dispatching the workflow manually")
        status, data = github_request(
            "POST", f"/repos/{owner}/{args.repo}/actions/workflows/build-ipa.yml/dispatches", token, {
                "ref": "main",
                "inputs": {
                    "bundle_id": args.bundle_id,
                    "app_group": args.app_group,
                    "display_name": args.display_name,
                    "sign_mode": args.sign_mode,
                },
            })
        if status not in (204, 201, 200):
            log(f"ERROR: workflow_dispatch failed ({status}): {data}")
            return 2
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            status, data = github_request("GET",
                f"/repos/{owner}/{args.repo}/actions/runs?event=workflow_dispatch&per_page=5", token)
            if status == 200 and data.get("workflow_runs"):
                run = data["workflow_runs"][0]
                created = datetime.fromisoformat(run["created_at"].replace("Z", "+00:00"))
                if datetime.now(timezone.utc) - created < timedelta(minutes=5):
                    run_id = run["id"]
                    log(f"found dispatched run #{run_id}")
                    break
            time.sleep(8)

    if not run_id:
        log(f"ERROR: no workflow run appeared. Check {actions_url}")
        return 2

    # 5. Poll until it finishes.
    log(f"polling run #{run_id} (timeout {args.timeout} min) ...")
    deadline = time.monotonic() + args.timeout * 60
    last_status = ""
    conclusion = None
    while time.monotonic() < deadline:
        status, run = github_request("GET", f"/repos/{owner}/{args.repo}/actions/runs/{run_id}", token)
        if status == 200:
            current = f"{run.get('status')}/{run.get('conclusion')}"
            if current != last_status:
                log(f"  run state: {current}")
                last_status = current
            if run.get("status") == "completed":
                conclusion = run.get("conclusion")
                break
        time.sleep(15)

    if conclusion is None:
        log(f"ERROR: timed out. Watch it at {actions_url}/runs/{run_id}")
        return 2
    if conclusion != "success":
        log(f"ERROR: workflow concluded '{conclusion}'. Logs: {actions_url}/runs/{run_id}")
        return 2

    # 6. Download the artifact and extract the IPA.
    status, data = github_request("GET", f"/repos/{owner}/{args.repo}/actions/runs/{run_id}/artifacts", token)
    artifacts = data.get("artifacts", []) if status == 200 else []
    artifact = next((a for a in artifacts if a["name"].startswith("SandboxExplorer-IPA")), None)
    if not artifact:
        log(f"ERROR: no IPA artifact in run #{run_id}: {data}")
        return 2

    DIST.mkdir(exist_ok=True)
    status, blob = github_request("GET",
        f"/repos/{owner}/{args.repo}/actions/artifacts/{artifact['id']}/zip", token, raw=True)
    if status != 200 or not isinstance(blob, bytes):
        log(f"ERROR: artifact download failed ({status})")
        return 2
    archive_path = DIST / "github-artifact.zip"
    archive_path.write_bytes(blob)

    extracted = []
    with zipfile.ZipFile(io.BytesIO(blob)) as archive:
        for name in archive.namelist():
            if name.lower().endswith(".ipa") or name.endswith("build-report.txt") \
               or name.endswith("SandboxExplorer.entitlements.plist") \
               or name.endswith("SandboxExplorer.embedded-entitlements.plist") \
               or name.endswith("xcodebuild.log"):
                target = DIST / Path(name).name
                target.write_bytes(archive.read(name))
                extracted.append(target)

    ipas = [p for p in extracted if p.suffix == ".ipa"]
    # Prefer the IPA that already carries the entitlements.
    ipa = (next((p for p in ipas if "-adhoc" in p.name), None)
           or next((p for p in ipas if "-signed" in p.name), None)
           or (ipas[0] if ipas else None))
    log("build succeeded")
    for path in extracted:
        log(f"  {path}  ({path.stat().st_size} bytes)")
    if not ipa:
        log("ERROR: artifact contained no .ipa")
        return 2
    log(f"\nIPA READY: {ipa}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        log("interrupted")
        sys.exit(130)
