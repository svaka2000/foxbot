--- Bring the right thing to the front: the terminal tab a session ran in, its
--- project folder in Finder, or that folder in your editor.
---
--- The original pet assumed Terminal.app for everyone, so an iTerm or Ghostty
--- user clicking a card got a brand new Terminal window instead of their
--- session. The hook now records which app actually owns the session (walked up
--- the process tree), and this module focuses that app — dropping down to an
--- exact tab match on the two terminals that expose one over AppleScript.

local Focus = {}

-- Apps we know how to raise. `tabs` means AppleScript can select the exact tab
-- for a given tty; everything else just gets activated, which is still the
-- right window on the vast majority of setups.
local TERMINALS = {
  ["Terminal"]  = { app = "Terminal",   tabs = "terminal" },
  ["iTerm2"]    = { app = "iTerm",      tabs = "iterm"    },
  ["iTerm"]     = { app = "iTerm",      tabs = "iterm"    },
  ["Ghostty"]   = { app = "Ghostty"  },
  ["WezTerm"]   = { app = "WezTerm"  },
  ["kitty"]     = { app = "kitty"    },
  ["Alacritty"] = { app = "Alacritty" },
  ["Warp"]      = { app = "Warp"     },
  ["Hyper"]     = { app = "Hyper"    },
  ["Tabby"]     = { app = "Tabby"    },
  ["Rio"]       = { app = "Rio"      },
  ["Code"]      = { app = "Visual Studio Code" },
  ["Cursor"]    = { app = "Cursor"   },
  ["Windsurf"]  = { app = "Windsurf" },
  ["Zed"]       = { app = "Zed"      },
  ["JetBrains"] = { app = "IntelliJ IDEA" },
}

-- Editors tried in order when opening a project folder, first one installed
-- wins. Bundle ids rather than names so a renamed .app still resolves.
local EDITORS = {
  { id = "com.microsoft.VSCode",     label = "VS Code" },
  { id = "com.todesktop.230313mzl4w4u92", label = "Cursor" },
  { id = "dev.zed.Zed",              label = "Zed" },
  { id = "com.exafunction.windsurf", label = "Windsurf" },
  { id = "com.sublimetext.4",        label = "Sublime Text" },
  { id = "com.apple.dt.Xcode",       label = "Xcode" },
}

local TAB_SCRIPTS = {
  terminal = [[
tell application "Terminal"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      try
        if tty of t is "%s" then
          set selected tab of w to t
          set index of w to 1
          return "ok"
        end if
      end try
    end repeat
  end repeat
  return "notfound"
end tell
]],

  iterm = [[
tell application "iTerm"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        try
          if tty of s is "%s" then
            select w
            select t
            select s
            return "ok"
          end if
        end try
      end repeat
    end repeat
  end repeat
  return "notfound"
end tell
]],
}

--- A tty is only ever interpolated into AppleScript after matching the exact
--- shape `ps` produces. Anything else could smuggle in script of its own.
local function safeTty(tty)
  return tty and tty:match("^/dev/tty[a-zA-Z0-9]+$") and tty or nil
end

local function resolve(name)
  if not name or name == "" then return nil end
  if TERMINALS[name] then return TERMINALS[name] end

  -- Tolerate variants like "WezTerm-gui" or "iTerm2 Beta" without needing an
  -- entry per build.
  for key, entry in pairs(TERMINALS) do
    if name:lower():find(key:lower(), 1, true) then return entry end
  end
  return nil
end

--- Focus the terminal tab that ran a session.
--- @param tty string  e.g. "/dev/ttys003"
--- @param app string  owning app as recorded by the hook, e.g. "Ghostty"
function Focus.terminal(tty, app)
  local entry = resolve(app)
  local safe = safeTty(tty)

  -- Exact tab, when the terminal supports it and we trust the tty.
  if entry and entry.tabs and safe then
    local script = TAB_SCRIPTS[entry.tabs]
    local ok, result = hs.osascript.applescript(string.format(script, safe))
    if ok and result == "ok" then return true end
  end

  -- Otherwise raise whichever app owns it. Only fall back to Terminal.app when
  -- we genuinely have no idea — never silently, the way the original did.
  if entry then
    hs.application.launchOrFocus(entry.app)
    return true
  end

  if safe then
    local ok, result = hs.osascript.applescript(string.format(TAB_SCRIPTS.terminal, safe))
    if ok and result == "ok" then return true end
  end
  return false
end

--- Reveal the project folder in Finder.
function Focus.reveal(path)
  if not path or path == "" then return false end
  if not hs.fs.attributes(path) then return false end
  hs.execute(("open -R %q"):format(path))
  return true
end

--- Open the project folder in the first editor that is actually installed.
function Focus.editor(path)
  if not path or path == "" then return false end
  if not hs.fs.attributes(path) then return false end

  for _, editor in ipairs(EDITORS) do
    if hs.application.pathForBundleID(editor.id) then
      hs.execute(("open -b %q %q"):format(editor.id, path))
      return true, editor.label
    end
  end

  hs.execute(("open %q"):format(path))   -- Finder, rather than nothing at all
  return false
end

--- Label of the editor a card's "open in editor" action would actually use.
function Focus.editorLabel()
  for _, editor in ipairs(EDITORS) do
    if hs.application.pathForBundleID(editor.id) then return editor.label end
  end
  return "Finder"
end

return Focus
