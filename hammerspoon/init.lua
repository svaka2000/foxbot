-- Hammerspoon config

foxbot = require("foxbot")

-- OPTIONAL — off by default, deliberately.
--
-- Turning this on lets *any* process on your Mac run arbitrary Lua inside
-- Hammerspoon through `osascript`, which means running code as you. It's handy
-- for debugging, but it is a real privilege-escalation surface, so it should be
-- a decision you make rather than a default you inherited.
--
-- Foxbot doesn't need it. Everything is in his menu, and Hammerspoon's own
-- Console (hammer icon -> Console) runs the same commands without opening the
-- door to anything else.
--
-- hs.allowAppleScript(true)
