--- The only file in this project that touches the network.
---
--- Everything else works with no account, no key and no connection, and CI
--- enforces that by failing the build if a network call appears anywhere but
--- here. This exists because a shipped pack of tips can tell you something
--- about git, and it cannot tell you something about the language you happen
--- to be writing right now.
---
--- ## It is off unless you turn it on, twice
---
--- Nothing here runs unless BOTH:
---
---   1. `~/.claude/foxbot/groq.key` exists and holds an API key you put there;
---   2. the "Fresh tips" switch is on, which it is not by default.
---
--- A key sitting on disk is not consent. The switch is the consent.
---
--- ## What leaves your machine
---
--- The file extensions found in the project folder, and nothing else. Not the
--- folder name, not file names, not paths, not a line of code, not what
--- Claude is doing, not what app you are in. The request body is small enough
--- to read in full, and `Remote.describe()` returns exactly what would be sent
--- so you can look at it before deciding.
---
--- ## Why it asks which models exist
---
--- Hosted model names are retired on a schedule nobody downstream controls,
--- and a hardcoded one turns into a 404 some months after release — in a
--- background feature, silently. So it asks for the list and takes the best
--- one actually being served.

local Remote = {}

Remote.HOST = "https://api.groq.com/openai/v1"
Remote.KEY_FILE = os.getenv("HOME") .. "/.claude/foxbot/groq.key"

-- Best first. Anything not on this list is still usable — the list is a
-- preference, not a whitelist, so a model released after this was written
-- doesn't render the feature dead.
Remote.PREFER = {
  "llama-3.3-70b-versatile",
  "openai/gpt-oss-120b",
  "qwen/qwen3.6-27b",
  "llama-3.1-8b-instant",
}

-- Models that exist but cannot answer this: speech, moderation, guards.
local function isChat(id)
  return not (id:find("whisper") or id:find("prompt%-guard")
              or id:find("orpheus") or id:find("safeguard"))
end

--- The key, or nil. Read each time rather than cached, so removing the file
--- turns the feature off immediately rather than at the next restart.
function Remote.key()
  local file = io.open(Remote.KEY_FILE, "r")
  if not file then return nil end
  local text = file:read("*a") or ""
  file:close()
  local key = text:gsub("%s+", "")
  return key ~= "" and key or nil
end

function Remote.available()
  return Remote.key() ~= nil
end

--- Which languages are in a folder. Extensions only, counted, top few —
--- deliberately the least identifying thing that is still useful.
function Remote.languages(folder, ls)
  if not folder or folder == "" then return {} end
  ls = ls or function(path)
    local out = {}
    local pipe = io.popen("/usr/bin/find " .. ("%q"):format(path)
                          .. " -maxdepth 2 -type f -name '*.*' 2>/dev/null | head -400")
    if not pipe then return out end
    for line in pipe:lines() do out[#out + 1] = line end
    pipe:close()
    return out
  end

  local counts = {}
  for _, path in ipairs(ls(folder)) do
    local ext = path:match("%.([%w_]+)$")
    if ext and #ext <= 5 then counts[ext] = (counts[ext] or 0) + 1 end
  end

  local order = {}
  for ext in pairs(counts) do order[#order + 1] = ext end
  table.sort(order, function(a, b)
    if counts[a] ~= counts[b] then return counts[a] > counts[b] end
    return a < b            -- stable, so the same folder always describes the same
  end)

  local top = {}
  for i = 1, math.min(4, #order) do top[i] = order[i] end
  return top
end

--- Exactly what would be sent, as a string, for the "what does this send?"
--- row in the menu. If this and the request body ever disagree, the row is a
--- lie, so the request is built from this.
function Remote.describe(languages)
  if #languages == 0 then return "nothing — no languages detected" end
  return "file extensions only: " .. table.concat(languages, ", ")
end

local function prompt(languages)
  return "Give me exactly one short, genuinely useful tip for a developer "
      .. "working in: " .. table.concat(languages, ", ") .. ".\n\n"
      .. "Rules: one sentence, under 140 characters, no preamble, no greeting, "
      .. "no markdown, no quotes around it. Something a working developer might "
      .. "not know — not 'write tests' or 'use version control'. If you are not "
      .. "confident it is true, pick a different tip."
end

-- The chosen model, once per session. Cheap to re-resolve if it fails.
local chosen = nil

local function pickModel(done)
  if chosen then return done(chosen) end

  local key = Remote.key()
  if not key then return done(nil) end

  hs.http.asyncGet(Remote.HOST .. "/models",
    { Authorization = "Bearer " .. key },
    function(status, body)
      if status ~= 200 then return done(nil) end
      local ok, parsed = pcall(hs.json.decode, body)
      if not ok or type(parsed) ~= "table" or type(parsed.data) ~= "table" then
        return done(nil)
      end

      local have = {}
      for _, model in ipairs(parsed.data) do
        if type(model.id) == "string" and isChat(model.id) then have[model.id] = true end
      end

      for _, id in ipairs(Remote.PREFER) do
        if have[id] then chosen = id return done(id) end
      end
      -- Nothing preferred is being served any more: take any chat model
      -- rather than going dark.
      local rest = {}
      for id in pairs(have) do rest[#rest + 1] = id end
      table.sort(rest)
      chosen = rest[1]
      done(chosen)
    end)
end

--- Ask for one tip. `done(text)` with the tip, or `done(nil)` for every
--- failure — no key, no network, a bad status, malformed JSON, an empty or
--- over-long answer. The caller falls back to the shipped pack, so there is
--- never an error to show and never a reason to retry.
---
--- @param languages string[]
--- @param done fun(text: string|nil)
function Remote.tip(languages, done)
  if #languages == 0 then return done(nil) end

  local key = Remote.key()
  if not key then return done(nil) end

  pickModel(function(model)
    if not model then return done(nil) end

    local body = hs.json.encode({
      model = model,
      max_tokens = 120,
      temperature = 0.9,
      messages = { { role = "user", content = prompt(languages) } },
    })

    hs.http.asyncPost(Remote.HOST .. "/chat/completions", body,
      { Authorization = "Bearer " .. key, ["Content-Type"] = "application/json" },
      function(status, reply)
        if status ~= 200 then
          -- A retired model is the likely cause, so let the next call
          -- re-resolve rather than failing forever on a cached name.
          if status == 404 or status == 400 then chosen = nil end
          return done(nil)
        end

        local ok, parsed = pcall(hs.json.decode, reply)
        if not ok or type(parsed) ~= "table" then return done(nil) end
        local choice = (parsed.choices or {})[1]
        local text = choice and choice.message and choice.message.content
        if type(text) ~= "string" then return done(nil) end

        text = Remote.tidy(text)
        if text == "" or #text > 200 then return done(nil) end
        done(text)
      end)
  end)
end

--- Models like to open with "Sure!" and wrap things in quotes and asterisks
--- however firmly you ask them not to. This is not a safety measure, it is
--- typography: a note in this panel is one plain sentence.
function Remote.tidy(text)
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("^[Ss]ure[,!.]?%s*", "")
  text = text:gsub("^[Hh]ere'?s? [%w%s]-:%s*", "")
  text = text:gsub("^[%-%*•]%s*", "")
  text = text:gsub("%*%*", ""):gsub("^\"(.*)\"$", "%1"):gsub("^'(.*)'$", "%1")
  -- Only the first sentence, if it produced several anyway.
  local first = text:match("^(.-[%.%?!])%s+%u")
  return first or text
end

return Remote
