--- How he phrases things.
---
--- Each voice covers every event, with a couple of variants so he doesn't read
--- out the identical string twice in a row. Lines are written to sit after the
--- session name, so they start lower-case and finish the sentence.

local Voice = {}

Voice.order = { "plain", "warm", "keen", "dry", "steward", "scamp", "feral" }

local voices = {
  plain = {
    label = "Plain", note = "says what happened",
    settled = { "finished.", "that's done." },
    running = { "started.", "off and running." },
    asking  = { "needs an answer.", "is asking you something." },
    idling  = { "has been waiting a while.", "is still waiting on you." },
    broke   = { "hit an error.", "stopped on a failure." },
    closed  = { "closed." },
  },

  warm = {
    label = "Warm", note = "gentle about it",
    settled = { "all wrapped up — have a look when you can.",
                "that's finished, whenever you're ready." },
    running = { "just started on it.", "is working on that now." },
    asking  = { "has a question for you when you have a second.",
                "would like your input on something." },
    idling  = { "is still waiting — no rush at all.",
                "has been holding for you a little while." },
    broke   = { "ran into trouble and could use a hand.",
                "hit a snag — worth a look when you can." },
    closed  = { "closed — hope that went well." },
  },

  keen = {
    label = "Keen", note = "far too excited",
    settled = { "IS DONE. GO SEE.", "finished and it looks GOOD." },
    running = { "IS OFF. let it cook.", "started! here we go!" },
    asking  = { "NEEDS YOU. answer it!", "has a question — go go go!" },
    idling  = { "IS STILL WAITING. unblock it!", "has been stuck on you!" },
    broke   = { "BROKE. go look, go look!", "ERROR. all hands!" },
    closed  = { "closed. good run." },
  },

  dry = {
    label = "Dry", note = "unimpressed",
    settled = { "done, apparently.", "finished. thrilling." },
    running = { "started. we'll see.", "off it goes." },
    asking  = { "wants a decision from you.", "has questions. of course it does." },
    idling  = { "is still sat there waiting.", "continues to wait. patiently." },
    broke   = { "broke. shocking.", "failed. who could have foreseen it." },
    closed  = { "closed. that happened." },
  },

  steward = {
    label = "Steward", note = "impeccably formal",
    settled = { "has concluded, at your convenience.",
                "is complete. I took the liberty of tidying up." },
    running = { "has commenced work on your behalf.",
                "is attending to the matter presently." },
    asking  = { "requests a decision from you.",
                "awaits your selection on a question." },
    idling  = { "continues to await your instruction.",
                "has been standing by for some time now." },
    broke   = { "regrets to report a failure. Your attention is required.",
                "has encountered difficulty and cannot proceed unaided." },
    closed  = { "has been closed. Good day." },
  },

  scamp = {
    label = "Scamp", note = "a smug little fox",
    settled = { "done. i did that. o7", "finished. no notes >:3" },
    running = { "started. don't watch me 0_0", "off. shoo." },
    asking  = { "wants you to pick one. carefully >:3",
                "is asking. and staring. 0_0" },
    idling  = { "is STILL waiting. rude of you -_-",
                "has been sat there. alone. abandoned." },
    broke   = { "broke it. wasn't me >:3", "exploded. i watched. o_o" },
    closed  = { "closed. bye o7" },
  },

  feral = {
    label = "Feral", note = "barely holding it together",
    settled = { "DONE!! IT'S DONE!! COME LOOK!!", "FINISHED!!! LOOK AT IT!!" },
    running = { "IT'S GOING!! IT'S GOING!! DON'T TOUCH!!",
                "RUNNING RUNNING RUNNING!!" },
    asking  = { "IT ASKED SOMETHING!! ANSWER IT!!", "QUESTION!! THERE IS A QUESTION!!" },
    idling  = { "IT'S STILL WAITING!!! NOBODY IS HELPING IT!!",
                "HELLO?? IT'S BEEN WAITING!!" },
    broke   = { "IT BROKE!! IT BROKE!! I'M FINE!! IT BROKE!!",
                "ERROR!!! I AM NORMAL ABOUT THIS!!!" },
    closed  = { "it's over. it's over. i'm fine." },
  },
}

-- Hook kinds are named for what happened; voices are keyed by how it feels.
local FOR_KIND = {
  done  = "settled",
  busy  = "running",
  ask   = "asking",
  idle  = "idling",
  error = "broke",
  ["end"] = "closed",
  nudge = "idling",
}

Voice.fallback = "plain"

function Voice.get(name)
  return voices[name] or voices[Voice.fallback]
end

--- One line for this event, chosen at random from the variants.
function Voice.line(name, kind)
  local voice = Voice.get(name)
  local lines = voice[FOR_KIND[kind] or "settled"] or voice.settled
  return lines[math.random(#lines)]
end

--- The first variant — used to preview a voice in the menu.
function Voice.sample(name, kind)
  local voice = Voice.get(name)
  local lines = voice[FOR_KIND[kind or "done"] or "settled"] or voice.settled
  return lines[1]
end

return Voice
