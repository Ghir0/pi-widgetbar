#!/usr/bin/env python3
"""Read-only local Pi session summary for the Omarchy bar widget.

Reads session JSONL headers and message metadata only. Never outputs prompts,
tool arguments/results, provider auth, or model credentials.
"""
from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

_pi_dir = os.environ.get("PI_CODING_AGENT_DIR", "")
if not _pi_dir:
    _pi_dir = Path.home() / ".pi" / "agent"
SESSION_ROOT = Path(_pi_dir) / "sessions"
MAX_SESSIONS = 5000
MAX_FILE_BYTES = 16 * 1024 * 1024
ACTIVE_SECONDS = 120


def parse_timestamp(ts):
    if isinstance(ts, (int, float)):
        return float(ts)
    if isinstance(ts, str):
        try:
            s = ts
            if s.endswith("Z"):
                s = s[:-1] + "+00:00"
            dt = datetime.fromisoformat(s)
            return dt.timestamp() * 1000.0
        except Exception:
            pass
    return None


TOKEN_FIELDS = ("input", "output", "cacheRead", "cacheWrite", "reasoning", "totalTokens")


def empty_token_usage() -> dict:
    return {key: 0 for key in TOKEN_FIELDS}


def add_token_usage(target: dict, usage: dict) -> None:
    for key in TOKEN_FIELDS:
        value = usage.get(key, 0)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            target[key] += int(value)


COST_FIELDS = ("input", "output", "cacheRead", "cacheWrite", "total")


def empty_cost_usage() -> dict:
    return {key: 0.0 for key in COST_FIELDS}


def add_cost_usage(target: dict, usage: dict) -> bool:
    found = False
    for key in COST_FIELDS:
        value = usage.get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            target[key] += float(value)
            found = True
    return found


def extract_task_text(msg: dict) -> str:
    content = msg.get("content")
    if isinstance(content, str):
        text = content.strip()
        return text[:120] + ("..." if len(text) > 120 else "") if text else ""
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict):
                t = block.get("type")
                if t == "text":
                    text = block.get("text", "").strip()
                    if text:
                        return text[:120] + ("..." if len(text) > 120 else "")
                elif t == "thinking":
                    text = block.get("thinking", "").strip()
                    if text:
                        return text[:120] + ("..." if len(text) > 120 else "")
                elif t == "code":
                    text = block.get("code", "").strip()
                    if text:
                        return "[code] " + text[:110] + ("..." if len(text) > 110 else "")
    return ""


def session_summary(path: Path) -> dict | None:
    try:
        if path.stat().st_size > MAX_FILE_BYTES:
            return None
        with path.open("r", encoding="utf-8", errors="replace") as stream:
            first = stream.readline()
            header = json.loads(first)
            if header.get("type") != "session":
                return None

            lines = stream.readlines()
            messages = []
            tokens = empty_token_usage()
            today_tokens = empty_token_usage()
            costs = empty_cost_usage()
            today_costs = empty_cost_usage()
            has_cost = False
            today_has_cost = False
            today_utc = datetime.now(timezone.utc).date().isoformat()
            model = None
            provider = None
            thinking_level = None
            last_task = ""

            for line in lines:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue

                etype = entry.get("type")
                if etype == "model_change":
                    model = entry.get("modelId")
                    provider = entry.get("provider")
                elif etype == "thinking_level_change":
                    thinking_level = entry.get("thinkingLevel")
                elif etype == "message":
                    msg = entry.get("message") or {}
                    stamp = parse_timestamp(entry.get("timestamp") or msg.get("timestamp"))
                    role = msg.get("role")
                    stop_reason = msg.get("stopReason") or ""
                    raw_stop = msg.get("rawStopReason") or ""
                    usage = msg.get("usage") or {}
                    if role == "assistant" and isinstance(usage, dict):
                        add_token_usage(tokens, usage)
                        is_today = stamp is not None and datetime.fromtimestamp(stamp / 1000.0, timezone.utc).date().isoformat() == today_utc
                        if is_today:
                            add_token_usage(today_tokens, usage)
                        message_cost = usage.get("cost")
                        if isinstance(message_cost, dict):
                            has_cost = add_cost_usage(costs, message_cost) or has_cost
                            if is_today:
                                today_has_cost = add_cost_usage(today_costs, message_cost) or today_has_cost
                    if role in ("user", "assistant"):
                        task_text = extract_task_text(msg)
                        if task_text:
                            last_task = task_text
                    if role:
                        messages.append({
                            "role": role,
                            "timestamp": stamp,
                            "stopReason": stop_reason,
                            "rawStopReason": raw_stop,
                        })

            if not messages:
                started = parse_timestamp(header.get("timestamp"))
                return {
                    "id": header.get("id", path.stem),
                    "cwd": header.get("cwd", ""),
                    "startedAt": header.get("timestamp", ""),
                    "updatedAt": started,
                    "ageSeconds": None,
                    "messages": 0,
                    "tokens": tokens,
                    "todayTokens": today_tokens,
                    "cost": costs,
                    "todayCost": today_costs,
                    "hasCost": has_cost,
                    "todayHasCost": today_has_cost,
                    "status": "idle",
                    "active": False,
                    "model": model,
                    "provider": provider,
                    "thinkingLevel": thinking_level,
                    "lastTask": last_task,
                }

            last_msg = messages[-1]
            last_ts = last_msg["timestamp"]
            now_ms = time.time() * 1000.0
            age = max(0, int((now_ms - last_ts) / 1000)) if last_ts is not None else None
            active = age is not None and age <= ACTIVE_SECONDS

            status = "idle"
            if active:
                role = last_msg.get("role")
                if role == "assistant":
                    sr = last_msg.get("stopReason") or ""
                    rsr = last_msg.get("rawStopReason") or ""
                    if sr == "toolUse" or rsr == "tool_calls":
                        status = "working"
                    else:
                        status = "needs_response"
                elif role == "user":
                    status = "working"
                else:
                    status = "working"

            return {
                "id": header.get("id", path.stem),
                "cwd": header.get("cwd", ""),
                "startedAt": header.get("timestamp", ""),
                "updatedAt": last_ts,
                "ageSeconds": age,
                "messages": len(messages),
                "tokens": tokens,
                "todayTokens": today_tokens,
                "cost": costs,
                "todayCost": today_costs,
                "hasCost": has_cost,
                "todayHasCost": today_has_cost,
                "status": status,
                "active": active,
                "model": model,
                "provider": provider,
                "thinkingLevel": thinking_level,
                "lastTask": last_task,
            }
    except Exception:
        return None


def main() -> int:
    sessions = []
    try:
        files = SESSION_ROOT.glob("*/*.jsonl")
        for index, path in enumerate(files):
            if index >= MAX_SESSIONS:
                break
            item = session_summary(path)
            if item is not None:
                sessions.append(item)
    except OSError:
        pass

    sessions.sort(key=lambda x: x.get("updatedAt") or 0, reverse=True)
    active_sessions = [s for s in sessions if s.get("active")]

    global_status = "idle"
    if any(s["status"] == "working" for s in active_sessions):
        global_status = "working"
    elif any(s["status"] == "needs_response" for s in active_sessions):
        global_status = "needs_response"
    elif any(s["status"] == "idle" for s in active_sessions):
        global_status = "idle"

    latest = sessions[0] if sessions else None
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    today_sessions = [s for s in sessions if str(s.get("startedAt", "")).startswith(today)]
    token_usage = empty_token_usage()
    today_token_usage = empty_token_usage()
    cost_usage = empty_cost_usage()
    today_cost_usage = empty_cost_usage()
    has_cost = False
    today_has_cost = False
    for session in sessions:
        add_token_usage(token_usage, session.get("tokens") or {})
        add_token_usage(today_token_usage, session.get("todayTokens") or {})
        has_cost = add_cost_usage(cost_usage, session.get("cost") or {}) or has_cost
        today_has_cost = add_cost_usage(today_cost_usage, session.get("todayCost") or {}) or today_has_cost

    payload = {
        "ok": True,
        "sessionCount": len(sessions),
        "activeCount": len(active_sessions),
        "workingCount": sum(1 for s in active_sessions if s["status"] == "working"),
        "needsResponseCount": sum(1 for s in active_sessions if s["status"] == "needs_response"),
        "status": global_status,
        "activeSessions": active_sessions,
        "latest": latest,
        "sessions": sessions[:10],
        "todayCount": len(today_sessions),
        "tokenUsage": token_usage,
        "todayTokenUsage": today_token_usage,
        "costUsage": cost_usage,
        "todayCostUsage": today_cost_usage,
        "hasCost": has_cost,
        "todayHasCost": today_has_cost,
    }
    print(json.dumps(payload, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
