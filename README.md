<div align="center">

<img src="docs/foxbot.png" width="130" alt="Foxbot">

# Foxbot

**A fox who sits on your screen and tells you what your Claude Code sessions are doing — while they're doing it.**

Run more than one Claude Code session and you lose track of which one is
thinking, which one finished, and which one has been quietly blocked on a
question for twenty minutes. Foxbot puts a small fox on your desktop who
**glows blue while a session works**, **turns amber and keeps asking until you
answer a question**, and **goes green when it lands** — with how long it took
and what it cost in tokens.

**[Setup](#setup)** ·
**[What he does](#what-he-does)** ·
**[Questions](#he-wont-let-you-miss-a-question)** ·
**[Live notes](#live-progress-notes)** ·
**[Cost](#what-a-turn-cost)** ·
**[CLI](#from-a-terminal)** ·
**[How it works](#how-it-works)** ·
**[Security](SECURITY.md)**

</div>

---

# Setup

macOS only.

```bash
git clone https://github.com/svaka2000/foxbot.git
cd foxbot && ./install.sh
```

That installs Hammerspoon via Homebrew if you don't have it, puts the fox in
`~/.hammerspoon/foxbot/`, the hook in `~/.claude/hooks/`, and the `foxbot`
command in `~/.local/bin/`. Your existing hooks are left alone — `settings.json`
is backed up first and the installer only ever appends.

Then check him:

```bash
foxbot doctor
```

**No macOS permissions are required.** Hammerspoon asks for Accessibility on
first launch because Hammerspoon always does; the fox doesn't use it. Dragging
polls the mouse specifically so it works with that permission refused.

<details>
<summary><b>Or paste this into Claude Code and let it do the whole thing</b></summary>

<br>

```text
Install Foxbot from https://github.com/svaka2000/foxbot

Do all of it, don't ask me to run anything myself:

1. Clone the repo into ~/Downloads/current-projects (create the folder if needed).
   If it's already there, git pull instead.
2. Run ./install.sh and show me any errors. It installs Hammerspoon via Homebrew
   if missing, copies the fox to ~/.hammerspoon/foxbot/, the hook to
   ~/.claude/hooks/foxbot.sh, and the `foxbot` CLI to ~/.local/bin/. Then it wires
   the hook into my ~/.claude/settings.json under UserPromptSubmit, PostToolUse,
   Stop, SessionEnd, Notification and PreToolUse — WITHOUT removing hooks I
   already have. It backs that file up first; tell me where the backup went.
3. Confirm Hammerspoon is running (pgrep -x Hammerspoon) and that the fox appeared
   on the right edge of my screen. He sets launch-at-login himself, so don't
   change any Hammerspoon preferences by hand.
4. Print the hook entries from settings.json so I can see my own are still intact
   alongside the new ones.
5. Run ~/.local/bin/foxbot doctor and show me the output. Every line should say ok.
6. Do NOT enable Hammerspoon's AppleScript bridge. It is off by default on
   purpose and the install doesn't need it.

Then tell me in a few lines: where he is on screen, how to drag him, how to open
his menu, the hide/show and stats shortcuts, and how to get him back if I quit.
I do NOT need to grant Accessibility — say so if Hammerspoon warns about it.
```

</details>

Sessions already running pick the hooks up automatically. Next turn you send, he
goes blue; when it lands he tells you which one:

> **payments-api** &nbsp;&nbsp;&nbsp; `4m 12s · 51.5k`
> finished.
> · committed: add password reset
> · edited login.ts, token.ts

Click the note to jump to that session's terminal tab, or use the buttons along
the bottom to open the folder, open it in your editor, or copy the summary.

---

## What he does

| | |
|---|---|
| **Live status** | blue while a session runs, and a count in the menu bar |
| **Won't let you miss a question** | stays amber and keeps reminding you |
| **Per-turn timing and cost** | `4m 12s · 51.5k`, from the real transcript |
| **What actually changed** | summaries built from files and commands, not prose |
| **Live progress notes** | rate-limited, never repetitive |
| **Today / this week** | turns, time, tokens, per-project, streaks |
| **Any terminal** | iTerm, Ghostty, WezTerm, Warp, kitty, Alacritty, VS Code, Cursor, Zed |
| **Quiet hours** | plus automatic silence while you're screen sharing |
| **Catch-up** | one summary when you come back, not eleven stale notes |
| **Per project** | mute or re-voice a noisy one |
| **Your own sprite** | drop a PNG in `assets/` |
| **A CLI** | `foxbot today`, `now`, `week`, `doctor` |

## The moods

One drawing, five states. Shipping five sprites would mean five things to keep
in sync and redraw for every skin; a coloured badge plus a change in how he
moves carries the same information and stays true for any sprite you drop in.

| Badge | Mood | When |
|---|---|---|
| — | resting | nothing running |
| 🔵 blue, breathing fast | working | a session is mid-turn |
| 🟡 amber, pulsing | waiting on you | a question is unanswered — **stays** until you deal with it |
| 🟢 green | just finished | a turn landed |
| 🔴 red | broken | wire it yourself, see below |

## He won't let you miss a question

This is the failure the whole thing exists to prevent. A note lasts twelve
seconds. If you were in another window when Claude asked which database to use,
the session sits blocked indefinitely and nothing on screen says so.

So a question marks the session as **waiting** until something actually moves it
along:

- He **stays amber** for as long as anything is blocked. Waiting outranks
  working — something needs you more than it needs to keep going.
- The menu bar shows **`?2`** rather than `2`.
- Unanswered questions are **repeated at 1m, 5m and 15m**, then every fifteen
  minutes. Abandoned after six hours, on the assumption that terminal is gone.
- The clock runs from the **first** question, not the latest, so a follow-up
  doesn't reset how long you've been holding it up.

## Live progress notes

He tells you what's being applied to the project as it happens — not a
play-by-play, a periodic digest:

> **foxbot**
> committed: rewrite the panel as one canvas
> · edited panel.lua, sprite.lua
> · ran the tests

That one note covers four tool calls. The whole feature is built around shutting
up, because a pet that narrates everything is a pet you uninstall:

| Rule | Why |
|---|---|
| **One note per 2 minutes** | a busy minute is still one note |
| **Four per turn, ever** | a marathon turn can't produce thirty |
| **20-second settle first** | so a build two seconds before a commit can't take the headline and block it |
| **A milestone or ≥3 files** | one edited file isn't news |
| **Never repeats itself** | identical text to last time is dropped |
| **Silent while you're blocked** | a question already needs you |
| **Silent while away, hidden, muted, presenting, or in quiet hours** | every gate applies |
| **No sound, no hop, 7s fade** | ambient, not attention-grabbing |

The headline is whatever mattered most, not what happened last — ranked
deploy → commit → migrate → delete → push → merge → tests → build → install.

## What a turn cost

Claude Code's transcripts record token usage per message, so a finished note can
say what the work actually took. Two things make that harder than summing a
column, and both are handled:

- **Assistant entries are rewritten repeatedly as a message streams**, so the
  same tokens appear several times. They're deduplicated by `message.id`,
  keeping the last write.
- **A turn has to end somewhere.** It ends at the last real user prompt — a user
  entry whose content isn't a `tool_result`.

Subagent output is counted separately and peak context is a max, not a sum.

## From a terminal

```
$ foxbot today

foxbot · today

  turns          14
  working      2h 14m
  sessions        3
  tokens       412.0k
  streak       6 days

  where it went
  payments-api         ██████████████····  1h 22m   210.4k
  landing-page         █████·············     38m    88.1k
```

`today` · `week` · `now` · `recent [n]` · `projects` · `export [--csv]` ·
`doctor`. It only ever reads.

---

## How it works

Claude Code fires hooks. Each runs `~/.claude/hooks/foxbot.sh`, which reads the
payload on stdin and appends at most one JSON line to
`~/.claude/foxbot/inbox.jsonl`. Hammerspoon tails that file.

| Hook | Meaning |
|---|---|
| `UserPromptSubmit` | a turn started — start the clock |
| `PostToolUse` | something was applied — coalesced, mostly discarded |
| `Stop` | the turn finished — stop the clock, write the ledger |
| `PreToolUse` (`AskUserQuestion\|ExitPlanMode`) | a question is on screen |
| `Notification` (`idle_prompt`) | waiting on you |
| `SessionEnd` | the session closed |

Pairing the first two with `Stop` is where the live status, every duration and
every cost figure comes from.

**Cost on your hot path:** `PostToolUse` fires on every tool call, so the boring
majority — reads, searches, listings — is thrown away by a shell pattern in
**~7ms**, before Python ever starts. Only a qualifying call pays the full ~37ms,
and those are rare by design.

`error` is supported but not wired by the installer, because Claude Code has no
reliable "this turn failed" signal to hang it on. If you have your own way of
detecting failure, point a hook at `bash "$HOME/.claude/hooks/foxbot.sh" error`.

### Files

```
~/.hammerspoon/foxbot/          the fox
~/.claude/hooks/foxbot.sh       the hook
~/.local/bin/foxbot             the CLI
~/.claude/foxbot/inbox.jsonl    events in
~/.claude/foxbot/ledger.jsonl   finished turns, for the numbers
```

## Make him yours

Drop any PNG into `~/.hammerspoon/foxbot/assets/` and pick it under **Sprite**.
Aspect ratio is kept, so a tall drawing stays tall, and deleting the one you
were using falls back to the bundled fox rather than leaving a hole.

If your image came out of an image generator, run it through the importer
first:

```bash
python3 tools/import_sprite.py ~/Downloads/my-fox.png --name my-fox
```

Generators hand back "pixel art" that isn't — rendered at high resolution with
soft anti-aliased edges and tens of thousands of colours, plus a faint halo
where the background was keyed out. At 96 points that reads as mush. The
importer crops to the artwork, discards the halo, snaps every pixel to a small
palette, and writes it at twice the display size so it stays sharp on a Retina
screen. The bundled fox goes from 65,984 colours to 8.

There's also a fox authored as a pixel grid in code, if you'd rather edit one a
pixel at a time than draw it:

```bash
python3 tools/draw_fox.py     # writes assets/classic.png
```

## Tests

```bash
brew install lua
lua tests/run.lua      # 145 unit tests
./tests/hook.sh        # 65 integration tests against the real hook
```

The hook tests drive the actual script against a throwaway HOME. Most of them
assert that it stays *quiet* — that's the whole judgement call of the live
notes. Others exist because of specific bugs: the shell pre-filter must stay a
superset of the patterns Python matches, or a signal is discarded before Python
runs and the only symptom is a note that silently never mentions it.

CI runs both on every push, and additionally fails the build if a network call
appears anywhere or if the AppleScript bridge is ever enabled by default.

## Troubleshooting

Start with `foxbot doctor`.

**He didn't appear.** Hammerspoon menu bar icon → Console, look for a red line.
`foxbot.state()` in that console prints everything he currently thinks.

**He's stuck on "working".** A session that never reported finishing is retired
after 30 minutes.

**Lost him off-screen.** `⌃⌥⌘F` twice. If a monitor went away,
`defaults delete org.hammerspoon.Hammerspoon foxbot.settings` resets him.

**Nothing happens.** `grep foxbot ~/.claude/settings.json`, then
`tail -f ~/.claude/foxbot/inbox.jsonl`.

## Where the idea came from

The idea of a desktop pet driven by Claude Code's hooks comes from
[mattypark/claudeaiagentreminderguy](https://github.com/mattypark/claudeaiagentreminderguy).
Foxbot is a separate implementation written from scratch — no code, artwork or
text is carried across — but it wouldn't exist without having seen that first,
and it's only fair to say so.

## License

MIT — see [LICENSE](LICENSE).
