#!/bin/bash
# Foxbot uninstaller.
#
#   ./uninstall.sh           remove him, keep the ledger
#   ./uninstall.sh --all     remove the ledger and settings too

set -euo pipefail

HS="$HOME/.hammerspoon"
CLAUDE="$HOME/.claude"
SETTINGS="$CLAUDE/settings.json"

EVERYTHING=0
for arg in "$@"; do [ "$arg" = "--all" ] && EVERYTHING=1; done

say() { printf '  %s\n' "$1"; }

echo "==> Unwiring the hook"
if [ -f "$SETTINGS" ]; then
  BACKUP="$SETTINGS.backup.$(date +%s)"
  cp "$SETTINGS" "$BACKUP"
  say "backed up to $BACKUP"

  python3 - "$SETTINGS" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
removed = 0

for event, groups in list(hooks.items()):
    for group in list(groups):
        before = group.get("hooks", [])
        kept = [h for h in before if "foxbot.sh" not in h.get("command", "")]
        if len(kept) == len(before):
            continue
        removed += len(before) - len(kept)
        group["hooks"] = kept
        # Only drop a group this script emptied — never one that was already
        # empty and might be holding a matcher somebody wrote by hand.
        if not kept:
            groups.remove(group)
    if not groups:
        del hooks[event]

if not hooks:
    settings.pop("hooks", None)

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("  removed %d hook(s)" % removed)
PY
else
  say "no settings.json — nothing to unwire"
fi

echo "==> Removing the require"
if [ -f "$HS/init.lua" ] && grep -q 'require("foxbot")' "$HS/init.lua"; then
  cp "$HS/init.lua" "$HS/init.lua.backup.$(date +%s)"
  sed -i '' '/^-- Foxbot$/d; /require("foxbot")/d' "$HS/init.lua"
  say "done"
else
  say "not present"
fi

echo "==> Removing files"
rm -rf "$HS/foxbot"
rm -f "$CLAUDE/hooks/foxbot.sh"
rm -f "$HOME/.local/bin/foxbot"
say "done"

if [ "$EVERYTHING" -eq 1 ]; then
  echo "==> Removing the ledger, the wallet, your API key and settings"
  rm -rf "$CLAUDE/foxbot"
  defaults delete org.hammerspoon.Hammerspoon foxbot.settings 2>/dev/null || true
  say "done"
else
  echo "==> Keeping ~/.claude/foxbot — the ledger, your donuts and any"
  echo "    API key you put there. Pass --all to delete it."
fi

cat <<'DONE'

Uninstalled.

Hammerspoon itself is still installed and running. Reload it (hammer icon ▸
Reload Config) to drop the fox from this session, or quit it.

To remove Hammerspoon as well:  brew uninstall --cask hammerspoon
DONE
