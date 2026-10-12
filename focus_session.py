#!/usr/bin/env python3
"""Focus the Hyprland window hosting a Pi session, or launch Pi if none found.

Matches Foot terminal windows whose CWD matches the session directory.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


def get_pi_windows() -> list[dict]:
    try:
        result = subprocess.run(
            ["hyprctl", "clients", "-j"],
            capture_output=True,
            text=True,
            check=True,
        )
        clients = json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return []

    pi_windows = []
    for c in clients:
        if c.get("class") == "foot" and "\u03c0" in (c.get("title") or ""):
            pi_windows.append(c)
    return pi_windows


def get_pid_cwd(pid: int) -> str | None:
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return None


def get_child_pids(pid: int) -> list[int]:
    """Return all descendant PIDs of a given PID."""
    children = []
    try:
        for path in Path(f"/proc/{pid}/task").glob("*/children"):
            with path.open("r") as f:
                for token in f.read().split():
                    try:
                        child_pid = int(token)
                        children.append(child_pid)
                        children.extend(get_child_pids(child_pid))
                    except ValueError:
                        pass
    except (OSError, FileNotFoundError):
        pass
    return children


def get_all_cwds(pid: int) -> list[str]:
    """Return all cwds for a PID and its descendants."""
    cwds = []
    for p in [pid] + get_child_pids(pid):
        cwd = get_pid_cwd(p)
        if cwd:
            cwds.append(cwd)
    return cwds


def focus_address(address: str) -> bool:
    # Omarchy's Hyprland 0.56 uses the Lua dispatcher API; the legacy
    # `hyprctl dispatch focuswindow ...` syntax is parsed as invalid Lua.
    selector = json.dumps(f"address:{address}")
    code = f"hl.dispatch(hl.dsp.focus({{ window = {selector} }}))"
    try:
        result = subprocess.run(
            ["hyprctl", "eval", code],
            capture_output=True,
            text=True,
            check=True,
        )
        return "ok" in result.stdout.lower()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def focus_session(target_cwd: str) -> bool:
    if not target_cwd:
        return False
    target = Path(target_cwd).resolve()
    for window in get_pi_windows():
        pid = window.get("pid")
        address = window.get("address")
        if not isinstance(pid, int) or not address:
            continue
        if any(Path(cwd).resolve() == target for cwd in get_all_cwds(pid)):
            return focus_address(address)

    # Never focus an unrelated Pi window when the requested session did not match.
    return False


def main() -> int:
    target_cwd = sys.argv[1] if len(sys.argv) > 1 else ""
    if focus_session(target_cwd):
        return 0
    print(f"Could not focus a Pi window for session directory: {target_cwd or '(empty)'}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
