# Security & privacy

Foxbot reads your Claude Code sessions and draws them on your screen. That is a
sensitive place to sit, so here is exactly what it touches.

## What it reads

- The hook payload Claude Code sends on stdin.
- `~/.claude/sessions/*.json` — to resolve a session's name and process id.
- The tail of the session transcript — for the generated title, and on `Stop`
  for the token figures. The `busy` path never opens it.
- `ps` output for the session's process and its ancestors, to find the terminal
  it belongs to.

## What it writes

- `~/.claude/foxbot/inbox.jsonl` — one line per event, mode `0600`.
- `~/.claude/foxbot/ledger.jsonl` — finished turns, for the numbers.
- `~/.claude/foxbot/work/` — a small per-session scratch file used to coalesce
  progress notes, deleted when the turn ends.
- Hammerspoon's own preferences, under `foxbot.settings`.

That's the whole list. It does not read your code, your shell history, your
keychain, or anything outside those paths.

## Network

There isn't any. No HTTP client, no sockets, no telemetry, no update check, no
analytics. CI fails the build if a network call ever appears.

Your session titles, prompts and summaries never leave the machine.

## macOS permissions

None.

Hammerspoon asks for Accessibility on first launch because Hammerspoon asks
generically at startup — **the fox never uses it**. Dragging is implemented by
polling the mouse rather than with `hs.eventtap`, specifically so that it works
with the permission refused. Dismiss the prompt; everything still works.

## The AppleScript bridge stays off

Hammerspoon can expose a bridge (`hs.allowAppleScript(true)`) that lets *any*
process on your Mac run arbitrary Lua inside Hammerspoon — which means running
code as you. That's a real privilege-escalation surface.

The installer never enables it, the shipped `init.lua` has it commented out with
an explanation, and CI fails the build if that ever changes. The fox doesn't
need it: every control is in his menu.

He does *call out* to AppleScript to select a terminal tab. That's the opposite
direction and needs no bridge.

## Credentials

Session text quotes whatever you pasted into Claude, which can include secrets.
Every string that reaches the inbox — titles, prompts, questions, options,
summaries — goes through a scrubber first, covering OpenAI/Anthropic keys,
GitHub tokens and PATs, Slack tokens, AWS access keys, Google API keys and OAuth
tokens, JWTs, PEM private key headers, `key=`/`secret=`/`password=`/`token=`
assignments, and long opaque base64-ish blobs.

It runs **before** the line is written, so a matched secret never lands on disk
even briefly.

This is a safety net, not a guarantee — an unusual format can slip through.
Treat `~/.claude/foxbot/` as sensitive.

## Command injection

The tty is the only value ever interpolated into an AppleScript string, and it
is matched against `^/dev/tty[a-zA-Z0-9]+$` first and dropped if it doesn't fit,
so nothing from a session name or a path can smuggle in script of its own.

Paths handed to `open` are quoted and checked for existence first.

Shell commands from tool payloads are only ever **pattern-matched**, never run.

## The hook is on your hot path

`UserPromptSubmit`, `PostToolUse` and `Stop` fire constantly, so the hook is
written never to block a turn and never to fail one:

- All work happens in a Python block whose stderr is discarded.
- Every filesystem and `ps` call is wrapped, with timeouts on subprocesses.
- The script ends in `exit 0` unconditionally.
- `PostToolUse` discards the boring majority in a shell pattern before Python
  starts, and `busy` never touches the transcript.

If it breaks, your session carries on as though it weren't there.

## What the installer changes

- Installs Hammerspoon via Homebrew, if missing.
- Copies files to `~/.hammerspoon/foxbot/`, `~/.claude/hooks/`, `~/.local/bin/`.
- Appends `foxbot = require("foxbot")` to `~/.hammerspoon/init.lua`.
- Adds six hook entries to `~/.claude/settings.json`, **backing it up first**,
  in their own matcher groups, appending rather than replacing.
- Turns on launch-at-login, hides the Dock icon, shows the menu bar icon — once,
  on first run only.

`./uninstall.sh` reverses all of it and only removes hook entries whose command
it can see is its own.

## Reporting something

Open an issue. If it's sensitive, say so without the details and we'll take it
from there.
