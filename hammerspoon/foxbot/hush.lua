--- Knowing when to shut up.
---
--- A fox that pops a bubble over a screen share is a fox you uninstall. This
--- gates the sound and the note separately: during quiet hours, or while you
--- are presenting, the event is still tracked and still recorded — it just
--- doesn't interrupt.

local Hush = {}

-- Apps whose visible window means "do not draw on top of me".
local PRESENTING = {
  ["us.zoom.xos"] = "Zoom",
  ["com.microsoft.teams2"] = "Teams",
  ["com.microsoft.teams"] = "Teams",
  ["com.cisco.webexmeetingsapp"] = "Webex",
  ["com.apple.QuickTimePlayerX"] = "QuickTime",
  ["com.obsproject.obs-studio"] = "OBS",
  ["com.apple.Keynote"] = "Keynote",
  ["com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"] = "Meet",
}

--- Is `hour` inside [from, to)? Handles a window that wraps midnight, which is
--- the usual case — 22:00 through to 08:00.
function Hush.within(hour, from, to)
  if from == to then return false end
  if from < to then return hour >= from and hour < to end
  return hour >= from or hour < to
end

--- Which app, if any, is presenting right now.
function Hush.presenting()
  for bundle, label in pairs(PRESENTING) do
    local app = hs.application.get(bundle)
    if app and app:isRunning() then
      -- Running in the background is not presenting; it needs a visible window.
      local window = app:mainWindow()
      if window and window:isVisible() then return label end
    end
  end
  return nil
end

--- Is he paused, and until when?
function Hush.paused(settings, now)
  local until_ = settings.pauseUntil or 0
  now = now or os.time()
  if until_ <= now then return false end
  return true, until_
end

--- "back in 12m", for the menu bar tooltip.
function Hush.backIn(settings, now)
  local paused, until_ = Hush.paused(settings, now)
  if not paused then return nil end
  local left = until_ - (now or os.time())
  if left < 60 then return "back in a moment" end
  return "back in " .. math.ceil(left / 60) .. "m"
end

--- Should this be silenced, and should the note still appear?
--- Returns (silence, show, why).
function Hush.check(settings, when)
  -- Paused outranks everything: it is the button you press when you want it
  -- to stop right now.
  if Hush.paused(settings, when) then return true, false, "paused" end
  if settings.quiet then return true, true, "muted" end

  local presenting = Hush.presenting()
  if presenting then return true, false, presenting end

  if settings.hush then
    local hour = tonumber(os.date("%H", when or os.time()))
    if Hush.within(hour, settings.hushFrom or 22, settings.hushTo or 8) then
      return true, settings.hushSoftly == true, "quiet hours"
    end
  end

  return false, true, nil
end

function Hush.window(settings)
  return string.format("%02d:00 – %02d:00",
                       settings.hushFrom or 22, settings.hushTo or 8)
end

return Hush
