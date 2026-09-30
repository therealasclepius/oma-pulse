#!/usr/bin/python3
"""Small Todoist API adapter. Requests arrive on stdin; secrets never enter argv."""
import json
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = "https://api.todoist.com/api/v1/"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "omaowl"
DATA = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "omaowl"


class ApiError(Exception):
    pass


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".todoist-")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(value, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read(path, fallback):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return fallback


def saved_token():
    return read(CONFIG / "todoist.json", {}).get("token", "")


def request(token, path, body=None, request_id=None):
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    if request_id:
        headers["X-Request-Id"] = request_id
    req = urllib.request.Request(BASE + path, headers=headers,
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            raw = response.read(8 * 1024 * 1024)
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        messages = {401: "API key rejected. Reconnect Todoist with a valid key.",
                    403: "Todoist denied access to this action.",
                    404: "This task is no longer available. Refresh the list.",
                    429: "Todoist rate limit reached. Wait a minute, then refresh."}
        raise ApiError(messages.get(e.code, "Todoist request failed (HTTP %s)." % e.code)) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ApiError("Could not reach Todoist. Check your connection and refresh.") from None


def pages(token, path, params=None):
    result, cursor, seen = [], None, set()
    for _ in range(100):
        query = dict(params or {}, limit=200)
        if cursor:
            query["cursor"] = cursor
        payload = request(token, path + "?" + urllib.parse.urlencode(query))
        if not isinstance(payload, dict) or not isinstance(payload.get("results"), list):
            raise ApiError("Todoist returned an unexpected response.")
        result.extend(payload["results"])
        cursor = payload.get("next_cursor")
        if not cursor:
            return result
        if cursor in seen:
            raise ApiError("Todoist pagination stalled. Try refreshing.")
        seen.add(cursor)
    raise ApiError("Too many Todoist results to load safely.")


def sync(token):
    tasks = pages(token, "tasks")
    try:
        projects = {str(p["id"]): p.get("name", "") for p in pages(token, "projects")}
    except ApiError:
        projects = {}
    rows = [{"id": str(t["id"]), "title": t.get("content", ""), "done": False,
             "due": (t.get("due") or {}).get("date", ""),
             "recurring": bool((t.get("due") or {}).get("is_recurring")),
             "project": projects.get(str(t.get("project_id")), ""),
             "completedAt": 0} for t in tasks if not t.get("checked") and not t.get("is_deleted")]
    return sorted(rows, key=lambda t: (t["due"] or "9999", t["title"].casefold()))


def run(payload):
    action = payload.get("action", "sync")
    token = saved_token()
    if action == "disconnect":
        (CONFIG / "todoist.json").unlink(missing_ok=True)
        (DATA / "todoist-pending.json").unlink(missing_ok=True)
        (DATA / "todoist-reminder-pending.json").unlink(missing_ok=True)
        return {"ok": True, "connected": False, "tasks": []}
    if action == "connect":
        token = str(payload.get("token", "")).strip()
        if not re.fullmatch(r"[A-Za-z0-9_-]{16,512}", token):
            raise ApiError("Paste your Todoist API key, then choose Connect.")
        rows = sync(token)  # Verify before replacing a working credential.
        atomic(CONFIG / "todoist.json", {"token": token})
        return {"ok": True, "connected": True, "tasks": rows}
    if not token:
        return {"ok": True, "connected": False, "tasks": []}
    if action == "sync":
        return {"ok": True, "connected": True, "tasks": sync(token)}
    if action in ("reminders", "remind"):
        task_id = str(payload.get("id", ""))
        if not re.fullmatch(r"[A-Za-z0-9_-]+", task_id):
            raise ApiError("Invalid task identifier.")
        if action == "reminders":
            rows = pages(token, "reminders", {"task_id": task_id})
            return {"ok": True, "connected": True, "reminderTaskId": task_id,
                    "reminders": [r for r in rows if not r.get("is_deleted")]}
        try:
            when = datetime.fromisoformat(str(payload.get("when", "")).replace("Z", "+00:00"))
            if when.tzinfo is None or when <= datetime.now(timezone.utc):
                raise ValueError()
        except (ValueError, OverflowError):
            raise ApiError("Choose a reminder date and time in the future.") from None
        due_date = when.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        pending_path = DATA / "todoist-reminder-pending.json"
        pending = read(pending_path, {})
        if pending.get("task_id") != task_id or pending.get("when") != due_date:
            pending = {"task_id": task_id, "when": due_date, "request_id": str(uuid.uuid4())}
            atomic(pending_path, pending)
        reminder = request(token, "reminders", {"task_id": task_id, "reminder_type": "absolute",
                           "due": {"date": due_date}, "service": "push"}, pending["request_id"])
        if not isinstance(reminder, dict) or not reminder.get("id"):
            raise ApiError("Todoist returned an unexpected reminder response. Retry the same time.")
        pending_path.unlink(missing_ok=True)
        return {"ok": True, "connected": True, "reminderTaskId": task_id, "reminder": reminder}
    if action == "add":
        title = str(payload.get("title", "")).strip()[:500]
        if not title:
            raise ApiError("Enter a task first.")
        # Reuse the idempotency key if a response was lost after creation.
        pending_path = DATA / "todoist-pending.json"
        pending = read(pending_path, {})
        if pending.get("title") != title:
            pending = {"title": title, "request_id": str(uuid.uuid4())}
            atomic(pending_path, pending)
        if not pending.get("task_id"):
            task = request(token, "tasks/quick", {"text": title}, pending["request_id"])
            if not isinstance(task, dict) or not task.get("id"):
                raise ApiError("Todoist returned an unexpected response. Retry the same task.")
            # Let Todoist parse explicit dates, recurrence, projects, and labels.
            # Only supply Today when its parser found no due date.
            if not task.get("due"):
                pending.update(task_id=str(task["id"]), due_request_id=str(uuid.uuid4()))
                atomic(pending_path, pending)
        if pending.get("task_id"):
            try:
                request(token, "tasks/" + urllib.parse.quote(pending["task_id"], safe=""),
                        {"due_string": "today", "due_lang": "en"}, pending["due_request_id"])
            except ApiError:
                raise ApiError("Task created, but setting Today failed. Retry the same task to finish without creating a duplicate.") from None
        pending_path.unlink(missing_ok=True)
        return {"ok": True, "connected": True, "created": True}
    if action == "close":
        task_id = str(payload.get("id", ""))
        if not re.fullmatch(r"[A-Za-z0-9_-]+", task_id):
            raise ApiError("Invalid task identifier.")
        request(token, "tasks/" + urllib.parse.quote(task_id, safe="") + "/close", {}, str(uuid.uuid4()))
        return {"ok": True, "connected": True, "closed": task_id}
    raise ApiError("Unsupported Todoist action.")


def main():
    try:
        # Quickshell sends one JSON line. Do not wait for EOF: a reused process
        # input channel can stay open and otherwise leave every task disabled.
        raw = sys.stdin.readline(65537)
        if len(raw) > 65536:
            raise ApiError("Todoist request is too large.")
        payload = json.loads(raw)
        result = run(payload)
    except ApiError as e:
        result = {"ok": False, "connected": bool(saved_token()), "error": str(e)}
    except Exception:
        result = {"ok": False, "connected": bool(saved_token()), "error": "Could not finish the Todoist request. Saved credentials were preserved."}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
