#!/bin/bash
# Foxbot installer.
#
#   ./install.sh
#
# Puts the fox in ~/.hammerspoon, the hook in ~/.claude/hooks, the CLI in
# ~/.local/bin, and wires the hook into ~/.claude/settings.json without
# disturbing anything already in there.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS="$HOME/.hammerspoon"
CLAUDE="$HOME/.claude"
SETTINGS="$CLAUDE/settings.json"
BIN="$HOME/.local/bin"

say() { printf '  %s\n' "$1"; }

echo "==> Hammerspoon"
if [ -d "/Applications/Hammerspoon.app" ]; then
  say "already installed"
else
  if ! command -v brew >/dev/null 2>&1; then
    say "! Homebrew isn't installed, and Hammerspoon isn't either."
    say "  Install it from https://www.hammerspoon.org and run this again."
    exit 1
  fi
  say "installing via Homebrew…"
  brew install --cask hammerspoon
fi

echo "==> The fox"
mkdir -p "$HS/foxbot/assets" "$HS/foxbot/sounds"
cp "$HERE"/hammerspoon/foxbot/*.lua "$HS/foxbot/"
cp "$HERE"/hammerspoon/foxbot/assets/*.png "$HS/foxbot/assets/" 2>/dev/null || true
cp "$HERE"/hammerspoon/foxbot/sounds/README.txt "$HS/foxbot/sounds/" 2>/dev/null || true
say "$HS/foxbot"

if [ -f "$HS/init.lua" ]; then
  if grep -q 'require("foxbot")' "$HS/init.lua"; then
    say "already loaded from your init.lua"
  else
    cp "$HS/init.lua" "$HS/init.lua.backup.$(date +%s)"
    {
      echo ""
      echo "-- Foxbot"
      echo 'foxbot = require("foxbot")'
    } >> "$HS/init.lua"
    say "added to your existing init.lua"
  fi
else
  cp "$HERE/hammerspoon/init.lua" "$HS/init.lua"
  say "created $HS/init.lua"
fi

echo "==> The hook"
mkdir -p "$CLAUDE/hooks" "$CLAUDE/foxbot"
cp "$HERE/hooks/foxbot.sh" "$CLAUDE/hooks/foxbot.sh"
chmod +x "$CLAUDE/hooks/foxbot.sh"
say "$CLAUDE/hooks/foxbot.sh"

echo "==> The foxbot command"
mkdir -p "$BIN"
cp "$HERE/bin/foxbot" "$BIN/foxbot"
chmod +x "$BIN/foxbot"
case ":$PATH:" in
  *":$BIN:"*) say "$BIN/foxbot" ;;
  *) say "$BIN/foxbot"
     say "(add $BIN to your PATH to run it as just \`foxbot\`)" ;;
esac

echo "==> Wiring the hook into settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
BACKUP="$SETTINGS.backup.$(date +%s)"
cp "$SETTINGS" "$BACKUP"
say "backed up to $BACKUP"

python3 - "$SETTINGS" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# (event, matcher, argument)
#
# Every one of these is pinned to an exact matcher. Joining somebody's existing
# group would mean inheriting their matcher — landing the question hook inside a
# narrow one so it never fires, or the step hook inside a "*" so it fires for
# every tool. Own group, every time.
WIRING = [
    ("UserPromptSubmit", None,                            "busy"),
    ("PostToolUse",      None,                            "step"),
    ("Stop",             None,                            "done"),
    ("SessionEnd",       "*",                             "end"),
    ("Notification",     "idle_prompt",                   "idle"),
    ("PreToolUse",       "AskUserQuestion|ExitPlanMode",  "ask"),
]


def already_wired(groups):
    return any("foxbot.sh" in hook.get("command", "")
               for group in groups
               for hook in group.get("hooks", []))


for event, matcher, argument in WIRING:
    groups = hooks.setdefault(event, [])

    if already_wired(groups):
        print("  %-16s already wired" % event)
        continue

    # Find a group with exactly this matcher, or make one. Anything already in
    # that group stays where it is; we only ever append.
    target = None
    for group in groups:
        if group.get("matcher") == matcher:
            target = group
            break
    if target is None:
        target = {"hooks": []}
        if matcher:
            target["matcher"] = matcher
        groups.append(target)

    target.setdefault("hooks", []).append({
        "type": "command",
        "command": 'bash "$HOME/.claude/hooks/foxbot.sh" %s' % argument,
    })
    print("  %-16s wired" % event)

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PY

echo "==> Starting Hammerspoon"
if pgrep -x Hammerspoon >/dev/null; then
  say "already running — restarting so it picks the fox up"
  pkill -x Hammerspoon || true
  sleep 1
fi
open -a Hammerspoon

# The fox sets launch-at-login and the dock/menu icons himself on first run, so
# nothing here needs Hammerspoon's AppleScript bridge switched on.

cat <<'DONE'

Done.

  • He's on the right edge of your screen — drag him anywhere.
  • Blue while a session is working, amber while one is waiting on you
    (and he keeps asking), green when it lands.
  • Click him for the menu. The menu bar icon has the same one.
  • ⌃⌥⌘F hide/show · ⌃⌥⌘T today
  • From a terminal: foxbot today · foxbot now · foxbot doctor

Launch-at-login is on, so he comes back after a reboot.

No macOS permissions needed — ignore Hammerspoon's Accessibility warning.
Nothing here touches the network, and no scripting bridge is left enabled.
DONE
