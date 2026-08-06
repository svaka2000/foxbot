--- Things the fox can teach you.
---
--- A fixed pack, drawn without replacement. Shipping a pack rather than
--- generating one means this works with no key, no account and no network —
--- which is the whole posture of the project — and it means every line in here
--- was checked by a person rather than produced on demand and hoped about.
---
--- Drawing *without replacement* matters more than it sounds. A tool that says
--- something charming and then says it again a week later stops being charming
--- immediately, and the obvious `pack[random(#pack)]` repeats within a dozen
--- draws by the birthday problem. The bag empties before it refills, so you see
--- every one of these before you see any of them twice.

local Lore = {}
Lore.__index = Lore

-- tag -> how the note is titled.
Lore.TITLES = {
  git    = "A git thing",
  shell  = "A terminal thing",
  mac    = "A Mac thing",
  claude = "A Claude Code thing",
  world  = "Did you know",
  code   = "Computing history",
}

--- The pack. One idea each, short enough to read without stopping what you
--- were doing — a "fact" that takes four lines is a distraction, not a gift.
Lore.PACK = {
  -- ------------------------------------------------------------------ git
  { tag = "git", text = "`git reflog` remembers everywhere HEAD has been. A commit you lost to a bad reset is almost always still in there." },
  { tag = "git", text = "`git add -p` stages a file a hunk at a time, so one messy afternoon can still become several clean commits." },
  { tag = "git", text = "`git bisect run ./test.sh` finds the commit that broke something by itself, using the script's exit status." },
  { tag = "git", text = "`git commit --fixup <sha>` then `git rebase -i --autosquash` folds a correction back into the commit it belongs to." },
  { tag = "git", text = "`git log -S\"someString\"` finds the commits where that string appeared or disappeared. It's called the pickaxe." },
  { tag = "git", text = "`git switch` and `git restore` exist because `git checkout` was quietly doing two unrelated jobs." },
  { tag = "git", text = "`git stash -u` includes untracked files. Without the flag they stay behind, which is how stashes lose new files." },
  { tag = "git", text = "`git worktree add ../hotfix main` gives you a second working directory on the same repo — no stashing to switch branches." },
  { tag = "git", text = "`git blame -C` follows lines that moved between files, so you get the author who wrote it, not the one who moved it." },
  { tag = "git", text = "The hooks in `.git/hooks` are all disabled by their `.sample` extension. Drop the suffix and they start running." },
  { tag = "git", text = "`git diff --word-diff` is far easier to read than the line version when you're reviewing prose." },
  { tag = "git", text = "Git's own man page describes it as \"the stupid content tracker\"." },

  -- ---------------------------------------------------------------- shell
  { tag = "shell", text = "Ctrl-R searches your shell history backwards. Press it again to keep walking back through the matches." },
  { tag = "shell", text = "`cd -` goes back to the directory you were in before this one. It toggles." },
  { tag = "shell", text = "`!!` is the last command you ran, which is why `sudo !!` is the standard response to a permission error." },
  { tag = "shell", text = "Ctrl-A jumps to the start of the line and Ctrl-E to the end — the same keys work in most text fields on a Mac." },
  { tag = "shell", text = "In zsh, `**/*.lua` matches at any depth with no extra setting. Bash needs `shopt -s globstar` first." },
  { tag = "shell", text = "`du -sh * | sort -h` sorts folders by size with the units still attached." },
  { tag = "shell", text = "Anything written to `/dev/null` is discarded. It has been the standard rubbish bin since early Unix." },
  { tag = "shell", text = "`sudo` is short for \"superuser do\"." },
  { tag = "shell", text = "Ctrl-Z suspends a program and `fg` brings it back. Useful when you need the shell for one moment." },

  -- ------------------------------------------------------------------ mac
  { tag = "mac", text = "`pbcopy` and `pbpaste` are the clipboard as pipes: `cat notes.md | pbcopy` puts a file straight on it." },
  { tag = "mac", text = "`caffeinate -d` keeps the display awake for as long as it runs — handy for a long build you want to watch." },
  { tag = "mac", text = "`mdfind` is Spotlight from the terminal, so it searches the index instead of walking the disk like `find`." },
  { tag = "mac", text = "`open .` opens the current folder in Finder, and `open -a Preview file.pdf` opens it in a chosen app." },
  { tag = "mac", text = "`say \"the build finished\"` speaks out loud. Tacked onto the end of a slow command it's a decent alarm." },
  { tag = "mac", text = "Holding Option while clicking the Wi-Fi menu shows the details — channel, signal strength, transmit rate." },

  -- --------------------------------------------------------------- claude
  { tag = "claude", text = "A CLAUDE.md in a project is loaded into context every session, so anything you'd otherwise repeat belongs there." },
  { tag = "claude", text = "Hooks fire on events like UserPromptSubmit and Stop. That's exactly how the fox knows what's happening." },
  { tag = "claude", text = "`/clear` starts a fresh context. Cheaper and clearer than talking a long, confused session back around." },
  { tag = "claude", text = "Skills live in ~/.claude/skills. Each is a folder with a SKILL.md describing when to use it." },
  { tag = "claude", text = "`claude mcp` manages MCP servers — the tools an agent can reach beyond your files." },
  { tag = "claude", text = "Subagents get their own context window, so a big search doesn't spend yours." },

  -- ---------------------------------------------------------------- world
  { tag = "world", text = "An octopus has three hearts. Two feed the gills and one feeds everything else, and it stops when the animal swims." },
  { tag = "world", text = "A day on Venus is longer than its year: it turns once in about 243 Earth days and orbits in about 225." },
  { tag = "world", text = "Bananas are berries, botanically. Strawberries are not." },
  { tag = "world", text = "Wombats produce cube-shaped droppings, which don't roll away when used to mark territory." },
  { tag = "world", text = "Sharks are older than trees. Sharks go back about 400 million years, trees about 350." },
  { tag = "world", text = "The Anglo-Zanzibar War of 1896 is the shortest on record — it was over in well under an hour." },
  { tag = "world", text = "A shuffled deck of cards is almost certainly in an order no deck has ever been in: 52! is about 8 followed by 67 zeros." },
  { tag = "world", text = "Nintendo was founded in 1889, making playing cards. The consoles came a good deal later." },
  { tag = "world", text = "Teaching had begun at Oxford by 1096. Tenochtitlan, the Aztec capital, was founded in 1325." },
  { tag = "world", text = "Cleopatra lived closer in time to the Moon landing than to the building of the Great Pyramid." },
  { tag = "world", text = "The Eiffel Tower is about 15cm taller in summer: the iron expands in the heat." },
  { tag = "world", text = "Honeybees communicate the direction and distance of food by dancing in a figure of eight." },

  -- ----------------------------------------------------------------- code
  { tag = "code", text = "\"Computer\" was a job title before it was a machine — a person who did calculations, usually by hand." },
  { tag = "code", text = "In 1947 Grace Hopper's team taped a moth into a logbook: \"first actual case of bug being found\"." },
  { tag = "code", text = "Ada Lovelace's 1843 notes on the Analytical Engine contain what's generally called the first published algorithm." },
  { tag = "code", text = "Python is named after Monty Python, not the snake. The docs used to be full of spam and eggs for the same reason." },
  { tag = "code", text = "Lua means \"moon\" in Portuguese. It was written at PUC-Rio in Brazil, which is also why it's not an acronym." },
  { tag = "code", text = "Lua counts from 1, not 0. Nearly every bug in a Lua codebase written by a C programmer starts there." },
  { tag = "code", text = "The QWERTY layout predates the computer by decades — it was designed for mechanical typewriters." },
  { tag = "code", text = "An off-by-one error is common enough to have its own abbreviation, OBOE, and its own genre of joke." },
}

--- @param deps { settings, save, now, random }
function Lore.new(deps)
  deps = deps or {}
  local self = setmetatable({}, Lore)
  self.settings = deps.settings or {}
  self.save = deps.save or function() end
  self.now = deps.now or os.time
  self.random = deps.random or math.random
  self.pack = deps.pack or Lore.PACK
  return self
end

--- Indices still in the bag. Stored as the *unseen* set rather than the seen
--- one so that adding entries to the pack later doesn't strand them: a new
--- entry is simply an index nobody has recorded, and the refill picks it up.
function Lore:bag()
  local seen = {}
  for _, index in ipairs(self.settings.loreSeen or {}) do seen[index] = true end

  local left = {}
  for index = 1, #self.pack do
    if not seen[index] then left[#left + 1] = index end
  end
  return left
end

--- One item, never the same one twice until the pack runs out.
function Lore:pick()
  if #self.pack == 0 then return nil end

  local left = self:bag()
  if #left == 0 then
    self.settings.loreSeen = {}
    left = self:bag()
  end

  local index = left[self.random(#left)]
  local seen = self.settings.loreSeen or {}
  seen[#seen + 1] = index
  self.settings.loreSeen = seen
  self.save(self.settings)

  local item = self.pack[index]
  return { tag = item.tag, text = item.text,
           title = Lore.TITLES[item.tag] or "Did you know" }
end

--- Has one been offered today? The fox volunteers at most one a day; the menu
--- can ask for as many as you like.
function Lore:offeredToday(startOfDay)
  return (self.settings.loreOn or 0) >= startOfDay
end

function Lore:markOffered(at)
  self.settings.loreOn = at
  self.save(self.settings)
end

return Lore
