#!/bin/bash
# Foxbot — the bridge between Claude Code's hooks and the fox on your screen.
#
#   foxbot.sh busy | step | done | ask | idle | end | error
#
# Reads a hook payload on stdin and appends at most one JSON line to
# ~/.claude/foxbot/inbox.jsonl, which Hammerspoon tails.
#
# Never blocks a turn and never fails one: everything is wrapped, and it always
# exits 0.

KIND="${1:-done}"
PAYLOAD="$(cat)"

# `step` runs on PostToolUse, which fires after every single tool call. Starting
# Python that often would add tens of milliseconds to hundreds of calls a
# session, so the boring majority — reads, searches, listings — is discarded
# here in a couple of milliseconds instead.
if [ "$KIND" = "step" ]; then
  if ! printf '%s' "$PAYLOAD" | grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit|NotebookEdit|Task)"'; then
    printf '%s' "$PAYLOAD" | grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"Bash"' || exit 0
    # This pattern MUST stay a superset of the COMMANDS table further down. A
    # signal recognised there but missing here is thrown away before Python
    # ever runs, and the only symptom is a note that quietly never mentions it.
    # tests/hook.sh has a case per milestone to keep the two honest.
    printf '%s' "$PAYLOAD" | grep -qE 'git commit|git push|git merge|git rebase|npm (test|run|install|add|i )|yarn |pnpm |bun (test|run|add|install)|pytest|jest|vitest|mocha|rspec|phpunit|cargo (test|build|add)|go (test|build|get)|lua tests?/|pip3? install|brew install|gem install|rm -rf|rm -fr|tsc|make |vercel|netlify|railway|fly deploy|wrangler|heroku|alembic|prisma|drizzle-kit|db:migrate|docker (build|compose)|terraform (apply|plan)' || exit 0
  fi
fi

FOXBOT_KIND="$KIND" FOXBOT_PAYLOAD="$PAYLOAD" python3 - <<'PY' 2>/dev/null
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import time

KIND = os.environ.get("FOXBOT_KIND", "done")
RAW = os.environ.get("FOXBOT_PAYLOAD", "")

HOME = os.path.expanduser("~")
DEN = os.path.join(HOME, ".claude", "foxbot")
INBOX = os.path.join(DEN, "inbox.jsonl")
WORK = os.path.join(DEN, "work")          # per-session activity, mid-turn
SESSIONS = os.path.join(HOME, ".claude", "sessions")

# Live narration is the feature most likely to get this uninstalled, so every
# number here is picked to keep it quiet rather than to be thorough.
GAP = 120          # seconds between ambient notes
SETTLE = 20        # let a turn's opening moments coalesce before the first
BUDGET = 4         # ambient notes one turn may ever produce
FEW_FILES = 3      # edits alone are only news once there are a few


def payload():
    try:
        return json.loads(RAW) if RAW.strip() else {}
    except Exception:
        return {}


# ------------------------------------------------------------------ scrubbing

# Session text quotes whatever you pasted into Claude, so anything that looks
# like a credential is replaced before it can reach the disk or the screen.
SECRETS = [
    r"sk-[A-Za-z0-9_\-]{16,}",                       # OpenAI / Anthropic
    r"gh[pousr]_[A-Za-z0-9]{16,}",                   # GitHub
    r"github_pat_[A-Za-z0-9_]{20,}",
    r"xox[abprs]-[A-Za-z0-9\-]{10,}",                # Slack
    r"AKIA[0-9A-Z]{16}",                             # AWS
    r"ASIA[0-9A-Z]{16}",
    r"AIza[0-9A-Za-z_\-]{30,}",                      # Google
    r"ya29\.[A-Za-z0-9_\-]{20,}",                    # Google OAuth
    r"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}",   # JWT
    r"-----BEGIN[A-Z ]{0,40}PRIVATE KEY-----",
    r"(?i)\b(api[-_]?key|secret|passwd|password|token|bearer|auth)\b\s*[:=]\s*\S+",
    r"\b[A-Za-z0-9+/]{40,}={0,2}\b",                 # long opaque blobs
]


def scrub(text):
    for pattern in SECRETS:
        text = re.sub(pattern, "[hidden]", text)
    return text


def tidy(text, limit=None):
    """Collapse whitespace, strip markup, scrub, optionally trim."""
    text = re.sub(r"<[^>]*>", " ", text or "")
    text = " ".join(text.split())
    text = scrub(text)
    if limit and len(text) > limit:
        text = text[: limit - 1].rstrip() + "…"
    return text


# -------------------------------------------------------------------- session


def session_record(session_id):
    """Claude Code keeps a small json per live session, keyed by pid."""
    if not session_id:
        return {}
    for path in glob.glob(os.path.join(SESSIONS, "*.json")):
        try:
            with open(path) as f:
                record = json.load(f)
        except Exception:
            continue
        if record.get("sessionId") == session_id:
            return record
    return {}


def ps(pid, fields):
    try:
        return subprocess.run(["ps", "-p", str(pid), "-o", fields],
                              capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        return ""


def terminal_line(pid):
    if not pid:
        return ""
    out = ps(pid, "tty=")
    if not out or "?" in out:
        return ""
    return out if out.startswith("/dev/") else "/dev/" + out


# Matching on the .app bundle name rather than the executable is what makes
# this work for apps whose binary is called something else — Warp's is
# literally named "stable".
EMULATORS = {
    "terminal": "Terminal", "iterm": "iTerm2", "iterm2": "iTerm2",
    "ghostty": "Ghostty", "wezterm": "WezTerm", "wezterm-gui": "WezTerm",
    "kitty": "kitty", "alacritty": "Alacritty", "warp": "Warp",
    "warppreview": "Warp", "hyper": "Hyper", "tabby": "Tabby", "rio": "Rio",
    "visual studio code": "Code", "code": "Code", "code helper": "Code",
    "cursor": "Cursor", "windsurf": "Windsurf", "zed": "Zed",
}


def owning_app(pid):
    """Walk up the process tree until something recognisable turns up."""
    if not pid:
        return ""
    current, hops = pid, 0
    while current and int(current) > 1 and hops < 12:
        out = ps(current, "ppid=,comm=")
        if not out:
            return ""
        parts = out.split(None, 1)
        if len(parts) < 2:
            return ""
        parent, command = parts[0], parts[1].strip()

        candidates = []
        bundle = re.search(r"/([^/]+)\.app/", command)
        if bundle:
            candidates.append(bundle.group(1))
        candidates.append(os.path.basename(command))

        for name in candidates:
            found = EMULATORS.get(name.lower())
            if found:
                return found
        try:
            current, hops = int(parent), hops + 1
        except ValueError:
            return ""
    return ""


def real(path):
    try:
        return os.path.realpath(path)
    except Exception:
        return path or ""


def is_scratch(path):
    """Somewhere that means "this isn't a project".

    Short-lived helper sessions run in the macOS temp directory, whose last
    path component is a single letter — so naming a note after the folder gives
    you a note titled "T", several a minute, saying nothing.
    """
    if not path:
        return False
    here = real(path)
    for base in (tempfile.gettempdir(), "/tmp", "/private/tmp", "/var/folders"):
        base = real(base)
        if here == base or here.startswith(base + os.sep):
            return True
    return False


# Real places, but useless as a name — your own username tells you nothing.
BLAND = {"/", "/usr", "/var", "/etc", "/opt", "/Users", "/home"}


def is_bland(path):
    if not path:
        return True
    here = real(path)
    return here in BLAND or here == real(HOME)


def transcript_title(path):
    """Claude Code writes its own generated title into the transcript."""
    if not path or not os.path.exists(path):
        return "", ""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            f.seek(max(0, size - 200_000))
            tail = f.read().decode("utf-8", "ignore")
    except Exception:
        return "", ""

    title, asked = "", ""
    for line in reversed(tail.splitlines()):
        try:
            row = json.loads(line)
        except Exception:
            continue
        kind = row.get("type")
        if kind in ("ai-title", "custom-title") and not title:
            title = tidy(row.get("aiTitle") or row.get("customTitle") or "")
        elif kind == "last-prompt" and not asked:
            asked = tidy(row.get("lastPrompt") or "", 180)
        if title and asked:
            break
    return title, asked


# ------------------------------------------------------------------- activity

# What a shell command was actually doing. First match wins, so the specific
# patterns come before the general ones.
COMMANDS = [
    (r"\bgit\s+commit\b", "commit"),
    (r"\bgit\s+push\b", "push"),
    (r"\bgit\s+(merge|rebase)\b", "merge"),
    (r"\b(vercel|netlify|railway|heroku|wrangler)\b.*\b(deploy|publish|up)\b", "deploy"),
    (r"\bfly\s+deploy\b|\bterraform\s+apply\b", "deploy"),
    (r"\b(alembic|prisma|drizzle-kit)\b|\bdb:migrate\b", "migrate"),
    (r"\b(pytest|jest|vitest|mocha|rspec|phpunit)\b", "tests"),
    (r"\b(npm|yarn|pnpm|bun)\s+(run\s+)?test\b", "tests"),
    (r"\b(cargo|go)\s+test\b|\blua\s+tests?/", "tests"),
    (r"\b(npm|yarn|pnpm|bun)\s+run\s+build\b", "build"),
    (r"\b(cargo|go)\s+build\b|\btsc\b|\bnext\s+build\b|\bdocker\s+build\b", "build"),
    (r"\b(npm|yarn|pnpm|bun)\s+(install|add)\b", "install"),
    (r"\b(pip3?|brew|gem)\s+install\b|\bcargo\s+add\b|\bgo\s+get\b", "install"),
    (r"\brm\s+-[rf]{1,2}\b", "delete"),
]

SAYS = {
    "commit": "committed", "push": "pushed", "merge": "merged",
    "deploy": "deployed", "migrate": "ran a migration", "tests": "ran the tests",
    "build": "built it", "install": "installed packages",
    "delete": "deleted files", "agent": "sent a subagent off",
}

# Ranked by how much you would want to be told; the winner becomes the headline.
WEIGHT = ["deploy", "commit", "migrate", "delete", "push", "merge",
          "tests", "build", "install", "agent"]


def commit_subject(command):
    found = re.search(r"-m\s+(['\"])(.*?)(?<!\\)\1", command, re.S)
    if not found:
        return ""
    return " ".join(found.group(2).split("\n")[0].split())[:60]


def read_tool(tool, args):
    """(note, path) for one tool call. Either may be empty."""
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        return "", (args.get("file_path") or args.get("notebook_path") or "")
    if tool == "Task":
        return "agent", ""
    if tool == "Bash":
        command = args.get("command") or ""
        for pattern, note in COMMANDS:
            if re.search(pattern, command):
                if note == "commit":
                    subject = commit_subject(command)
                    return ("commit:" + subject) if subject else "commit", ""
                return note, ""
    return "", ""


def work_file(session_id):
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", session_id or "unknown")
    return os.path.join(WORK, safe + ".json")


def read_work(session_id):
    try:
        with open(work_file(session_id)) as f:
            found = json.load(f)
        return found if isinstance(found, dict) else {}
    except Exception:
        return {}


def write_work(session_id, state):
    try:
        os.makedirs(WORK, mode=0o700, exist_ok=True)
        with open(work_file(session_id), "w") as f:
            json.dump(state, f)
    except Exception:
        pass


def clear_work(session_id):
    try:
        os.remove(work_file(session_id))
    except Exception:
        pass


def fresh_work(now):
    # `pending` resets on every ambient note; `turn` accumulates for the whole
    # turn and is what the finishing summary is built from.
    return {"turn_at": now, "spoken": 0, "last": 0, "said": "",
            "pending": {"files": {}, "notes": []},
            "turn": {"files": {}, "notes": []}}


def note_into(bucket, note, path):
    if path:
        bucket["files"][path] = bucket["files"].get(path, 0) + 1
    if note and note not in bucket["notes"]:
        bucket["notes"].append(note)


def shared_folder(paths, root):
    """The shallowest directory holding all of them, relative to the project."""
    common = None
    for path in paths:
        here = os.path.dirname(path)
        rel = os.path.relpath(here, root) if root else here
        parts = [p for p in rel.split(os.sep) if p not in ("", ".")]
        if parts and parts[0] == "..":
            parts = []
        common = parts if common is None else [a for a, b in zip(common, parts) if a == b]
    return os.sep.join(common) if common else ""


def describe(bucket, root, always=False):
    """(headline, lines) for a bucket of activity.

    `always` forces a description even when very little happened — used at the
    end of a turn, where anything at all is worth reporting.
    """
    notes, files = bucket.get("notes") or [], bucket.get("files") or {}

    kinds = []
    for note in notes:
        kind = note.split(":", 1)[0]
        if kind not in kinds:
            kinds.append(kind)

    if not always and not kinds and len(files) < FEW_FILES:
        return "", []

    headline, subject = "", ""
    for kind in WEIGHT:
        if kind in kinds:
            headline = SAYS.get(kind, kind)
            if kind == "commit":
                for note in notes:
                    if note.startswith("commit:"):
                        subject = note.split(":", 1)[1]
                        break
            break

    lines = []
    if files:
        count = len(files)
        if count <= 3:
            lines.append("edited " + ", ".join(
                sorted(os.path.basename(p) for p in files)))
        else:
            where = shared_folder(list(files), root)
            lines.append("edited %d files%s" % (count, (" in " + where) if where else ""))

    for kind in WEIGHT:
        if kind in kinds and SAYS.get(kind) != headline:
            lines.append(SAYS.get(kind, kind))

    if not headline:
        headline = lines.pop(0) if lines else ""
    elif subject:
        headline = headline + ": " + subject

    return headline, lines


# --------------------------------------------------------------------- asking


def question(data, width=96):
    """(headline, options) for a session putting a question on screen.

    Claude Code renders its option pickers through AskUserQuestion and plan
    approval through ExitPlanMode, so the payload carries both before you ever
    see them.
    """
    tool = data.get("tool_name") or ""
    args = data.get("tool_input") or {}
    if not isinstance(args, dict):
        return "", []

    if tool == "ExitPlanMode":
        return "wants to start building", ["Approve the plan, or send it back"]

    asked = args.get("questions")
    if not isinstance(asked, list) or not asked:
        return "", []

    first = asked[0] if isinstance(asked[0], dict) else {}
    headline = tidy(first.get("question") or first.get("header") or "", width)
    if len(asked) > 1:
        headline = "%s  (1 of %d)" % (headline, len(asked))

    options = []
    for choice in (first.get("options") or []):
        if isinstance(choice, dict):
            label = tidy(choice.get("label") or "", width)
            if label:
                options.append(label)

    for extra in asked[1:]:
        if isinstance(extra, dict):
            options.append("then: " + tidy(extra.get("header")
                                           or extra.get("question") or "", width))
    return headline, options[:6]


# --------------------------------------------------------------------- tokens


def spend(path, cap=4_000_000):
    """What the finished turn cost.

    Assistant entries are rewritten repeatedly as a message streams, so the same
    tokens appear several times over — they are deduplicated by message id,
    keeping the last write. A turn ends at the last real user prompt, which is a
    user entry whose content is not a tool result.
    """
    if not path or not os.path.exists(path):
        return None
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            f.seek(max(0, size - cap))
            tail = f.read().decode("utf-8", "ignore")
    except Exception:
        return None

    seen = set()
    out = {"out": 0, "sub": 0, "context": 0, "messages": 0, "model": ""}

    for line in reversed(tail.splitlines()):
        try:
            row = json.loads(line)
        except Exception:
            continue
        kind = row.get("type")

        if kind == "user":
            content = (row.get("message") or {}).get("content")
            blocks = ([b.get("type") for b in content if isinstance(b, dict)]
                      if isinstance(content, list) else [])
            if "tool_result" not in blocks:
                break
            continue

        if kind != "assistant":
            continue

        message = row.get("message") or {}
        mid = message.get("id")
        if not mid or mid in seen:
            continue
        seen.add(mid)

        usage = message.get("usage") or {}
        tokens = usage.get("output_tokens") or 0
        if row.get("isSidechain"):
            out["sub"] += tokens
        else:
            out["out"] += tokens
        out["messages"] += 1
        out["context"] = max(out["context"],
                             (usage.get("input_tokens") or 0)
                             + (usage.get("cache_read_input_tokens") or 0)
                             + (usage.get("cache_creation_input_tokens") or 0))
        out["model"] = out["model"] or (message.get("model") or "")

    return out if out["messages"] else None


# ----------------------------------------------------------------------- main

data = payload()
session_id = data.get("session_id") or ""
record = session_record(session_id)

cwd = data.get("cwd") or record.get("cwd") or ""
folder = os.path.basename(cwd.rstrip("/")) if cwd else ""

scratch = is_scratch(cwd)
bland = scratch or is_bland(cwd)

# A throwaway session in the temp directory is not work worth interrupting for.
given = record.get("name") or ""
named = bool(given) and record.get("nameSource") != "derived"
if scratch and not named:
    sys.exit(0)

now = int(time.time())

# A turn starting resets the budget; a turn ending throws the tally away.
if KIND == "busy":
    write_work(session_id, fresh_work(now))
elif KIND in ("end", "error"):
    clear_work(session_id)

headline, lines = "", []

if KIND == "step":
    tool = data.get("tool_name") or ""
    args = data.get("tool_input") or {}
    if not isinstance(args, dict):
        sys.exit(0)

    note, path = read_tool(tool, args)
    if not note and not path:
        sys.exit(0)

    state = read_work(session_id) or fresh_work(now)
    state.setdefault("pending", {"files": {}, "notes": []})
    state.setdefault("turn", {"files": {}, "notes": []})
    note_into(state["pending"], note, path)
    note_into(state["turn"], note, path)

    def hold_it():
        write_work(session_id, state)
        sys.exit(0)

    if state.get("spoken", 0) >= BUDGET:
        hold_it()

    # Notes are spaced out, so a busy minute is still one note. The first of a
    # turn measures from when the turn began rather than from a previous note
    # there isn't one of — and `last` is legitimately 0 until then, so it has to
    # be tested explicitly rather than for truthiness.
    wait = GAP if state.get("spoken", 0) else SETTLE
    since = state.get("last") or 0
    if since <= 0:
        since = state.get("turn_at") or 0
    if since <= 0:
        since = now
    if now - since < wait:
        hold_it()

    headline, lines = describe(state["pending"], cwd)
    if not headline:
        hold_it()
    if headline == state.get("said"):      # never say the same thing twice
        hold_it()

    state["last"] = now
    state["spoken"] = state.get("spoken", 0) + 1
    state["said"] = headline
    state["pending"] = {"files": {}, "notes": []}
    write_work(session_id, state)

# Naming. A generated title beats the folder; the folder beats nothing; and a
# bland folder — your home directory, "/" — is worse than nothing.
title, asked = "", ""
if not named and KIND != "busy":
    title, asked = transcript_title(data.get("transcript_path", ""))

fallback = "" if bland else folder
session = scrub(given if named else (title or fallback or "claude"))

hint = "" if named else asked

if KIND == "step":
    hint, event_lines = headline, lines
elif KIND == "ask":
    hint, event_lines = question(data)
    if not hint and not event_lines:
        sys.exit(0)
elif KIND == "done":
    # What the turn actually did, taken from what it actually changed rather
    # than from what the assistant said about itself.
    state = read_work(session_id)
    turn = state.get("turn") if state else None
    summary, event_lines = ("", [])
    if turn:
        summary, event_lines = describe(turn, cwd, always=True)
        if summary:
            event_lines = [summary] + event_lines
    clear_work(session_id)
else:
    event_lines = []

event = {
    "ts": now,
    "kind": KIND,
    "session": session,
    "session_id": session_id,
    "named": named,
    "hint": hint,
    "lines": event_lines[:6],
    "cwd": cwd,
    "tty": terminal_line(record.get("pid")),
    "app": owning_app(record.get("pid")),
}

# Only group by a folder that identifies a project, or every session run from
# home lands in a bucket named after you.
if not bland:
    event["folder"] = folder

if KIND == "done":
    used = spend(data.get("transcript_path", ""))
    if used:
        event["tokens"] = used["out"]
        event["subTokens"] = used["sub"]
        event["context"] = used["context"]
        event["model"] = used["model"]

try:
    os.makedirs(DEN, mode=0o700, exist_ok=True)
    with open(INBOX, "a") as f:
        f.write(json.dumps(event) + "\n")
    os.chmod(INBOX, 0o600)
except Exception:
    pass
PY

exit 0
