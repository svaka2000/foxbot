#!/bin/bash
# Integration tests for the hook.
#
#   ./tests/hook.sh
#
# Drives hooks/foxbot.sh with real payloads against a throwaway HOME and asserts
# on what lands in the inbox. Most of this is about the live progress notes: the
# whole feature is a judgement call about when to shut up, and every rule that
# keeps it quiet is worth a test.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/hooks/foxbot.sh"

# Deliberately NOT under /tmp: the hook treats anything in the temp directory as
# a scratch session, which would make every case below silently pass.
SANDBOX="$REPO/.testhome"
PROJECT="$SANDBOX/work/my-app"

PASS=0
FAIL=0

reset() {
  rm -rf "$SANDBOX"
  mkdir -p "$PROJECT" "$SANDBOX/.claude/foxbot"
}

fire() {
  # fire <kind> <json payload>
  printf '%s' "$2" | HOME="$SANDBOX" bash "$HOOK" "$1"
}

inbox() { cat "$SANDBOX/.claude/foxbot/inbox.jsonl" 2>/dev/null; }
count()  { inbox | grep -c . ; }
clear_inbox() { rm -f "$SANDBOX/.claude/foxbot/inbox.jsonl"; }

# Pretend enough time has passed, without sleeping through it. Both clocks move:
# `turn` gates the first bubble of a turn, `last` gates every one after it.
#
# Note that a bubble is only ever produced *by* a tool call — nothing flushes on
# a timer — so every case below fires one more call after advancing, which is
# also how it behaves in a real session.
advance() {
  python3 - "$SANDBOX" <<'PY'
import json, os, sys, glob, time
# Wind the clocks back an hour rather than to zero: zero is a real value here
# (it means "no bubble yet this turn") and testing with it hides bugs.
old = int(time.time()) - 3600
for path in glob.glob(os.path.join(sys.argv[1], ".claude/foxbot/work/*.json")):
    with open(path) as f: state = json.load(f)
    if state.get("last"):
        state["last"] = old
    state["turn_at"] = old
    with open(path, "w") as f: json.dump(state, f)
PY
}

check() {
  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n       got:  %s\n       want: %s\n' "$1" "$2" "$3"
  fi
}

field() {
  # field <jsonline> <key>
  python3 -c "
import json,sys
try: print(json.loads(sys.argv[1]).get(sys.argv[2], ''))
except Exception: print('')
" "$1" "$2"
}

edit_payload() {
  printf '{"session_id":"s1","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' \
    "$PROJECT" "$1"
}

bash_payload() {
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s1','cwd':sys.argv[1],'tool_name':'Bash',
                  'tool_input':{'command':sys.argv[2]}}))
" "$PROJECT" "$1"
}

echo "foxbot hook tests"

# ---------------------------------------------------------------- noise floor

reset
fire step '{"session_id":"s1","cwd":"'"$PROJECT"'","tool_name":"Read","tool_input":{"file_path":"a.ts"}}'
fire step '{"session_id":"s1","cwd":"'"$PROJECT"'","tool_name":"Grep","tool_input":{"pattern":"x"}}'
fire step '{"session_id":"s1","cwd":"'"$PROJECT"'","tool_name":"Glob","tool_input":{"pattern":"*"}}'
check "reading tools say nothing" "$(count)" "0"

fire step "$(bash_payload 'ls -la')"
fire step "$(bash_payload 'cat README.md')"
fire step "$(bash_payload 'echo hello')"
check "boring shell commands say nothing" "$(count)" "0"

# One edit is not news. Nor are two.
reset
fire step "$(edit_payload "$PROJECT/src/a.ts")"
fire step "$(edit_payload "$PROJECT/src/b.ts")"
advance
fire step "$(edit_payload "$PROJECT/src/b.ts")"
check "one or two edited files say nothing" "$(count)" "0"

# Three is.
fire step "$(edit_payload "$PROJECT/src/c.ts")"
check "three edited files earn one note" "$(count)" "1"
check "and it names them" "$(field "$(inbox | tail -1)" hint)" "edited a.ts, b.ts, c.ts"

# --------------------------------------------------------- settle and cooldown

# Everything in the opening moments of a turn coalesces rather than racing to
# be the first bubble.
reset
fire step "$(bash_payload 'npm run build')"
fire step "$(bash_payload 'git commit -m "ship it"')"
check "a burst at the start of a turn stays silent" "$(count)" "0"

advance
fire step "$(edit_payload "$PROJECT/src/a.ts")"
check "then speaks once" "$(count)" "1"
check "and the commit leads, not the build" \
  "$(field "$(inbox | tail -1)" hint)" "committed: ship it"

clear_inbox
fire step "$(edit_payload "$PROJECT/src/d.ts")"
fire step "$(edit_payload "$PROJECT/src/e.ts")"
fire step "$(edit_payload "$PROJECT/src/f.ts")"
check "a burst inside the cooldown stays silent" "$(count)" "0"

advance
fire step "$(edit_payload "$PROJECT/src/g.ts")"
check "and speaks again once it passes" "$(count)" "1"

# ---------------------------------------------------------------- milestones

milestone() {
  # milestone <name> <command> <expected headline>
  reset
  fire step "$(bash_payload "$2")"
  advance
  fire step "$(bash_payload "$2")"
  check "$1 is a milestone" "$(count)" "1"
  check "$1 is labelled plainly" "$(field "$(inbox | tail -1)" hint)" "$3"
}

milestone "a commit"   'git commit -m "fix token refresh"' "committed: fix token refresh"
milestone "a test run" 'npx vitest run'                    "ran the tests"
milestone "installing" 'npm install react'                 "installed packages"
milestone "a delete"   'rm -rf build/'                     "deleted files"
milestone "a deploy"   'vercel deploy --prod'              "deployed"
milestone "a build"    'npm run build'                     "built it"

# The shell pre-filter has to stay a superset of the patterns Python matches on.
# Anything recognised downstream but missed up there is discarded before Python
# runs, and the only symptom is a note that silently never mentions it — which
# is exactly how `lua tests/` went missing.
milestone "pytest"     'pytest -q'                         "ran the tests"
milestone "go test"    'go test ./...'                     "ran the tests"
milestone "cargo test" 'cargo test'                        "ran the tests"
milestone "lua tests"  'lua tests/run.lua'                 "ran the tests"
milestone "pip"        'pip install requests'              "installed packages"
milestone "brew"       'brew install lua'                  "installed packages"
milestone "cargo add"  'cargo add serde'                   "installed packages"
milestone "go get"     'go get ./...'                      "installed packages"
milestone "a push"     'git push origin main'              "pushed"
milestone "a merge"    'git rebase main'                   "merged"
milestone "a migration" 'npx prisma migrate deploy'        "ran a migration"
milestone "tsc"        'npx tsc --noEmit'                  "built it"
milestone "cargo build" 'cargo build --release'            "built it"
milestone "docker"     'docker build -t app .'             "built it"
milestone "terraform"  'terraform apply -auto-approve'     "deployed"
milestone "fly"        'fly deploy'                        "deployed"

# ------------------------------------------------------------- repetition

reset
fire step "$(bash_payload 'npm test')"
advance
fire step "$(bash_payload 'npm test')"
check "first test run speaks" "$(count)" "1"

advance
fire step "$(bash_payload 'npm test')"
advance
fire step "$(bash_payload 'npm test')"
check "saying the identical thing again is suppressed" "$(count)" "1"

# ------------------------------------------------------------------ turn cap

reset
for i in 1 2 3 4 5 6 7 8 9 10; do
  fire step "$(bash_payload "git commit -m 'change number $i'")"
  advance
done
check "a turn is capped at four notes however long it runs" "$(count)" "4"

# A new turn starts the budget again.
fire busy '{"session_id":"s1","cwd":"'"$PROJECT"'","transcript_path":""}'
clear_inbox
fire step "$(bash_payload 'git commit -m "after the reset"')"
advance
fire step "$(bash_payload 'git commit -m "after the reset"')"
check "a new turn speaks again" "$(count)" "1"

# Finishing a turn throws the tally away entirely.
fire done '{"session_id":"s1","cwd":"'"$PROJECT"'","transcript_path":""}'
check "the work state is cleared on done" \
  "$(ls "$SANDBOX/.claude/foxbot/work" 2>/dev/null | grep -c . )" "0"

# ------------------------------------------------------------- scratch dirs

reset
TMPD="$(python3 -c 'import tempfile;print(tempfile.gettempdir())')/somewhere"
mkdir -p "$TMPD"
fire done '{"session_id":"s2","cwd":"'"$TMPD"'","transcript_path":""}'
check "a temp-dir session is never announced" "$(count)" "0"

fire done '{"session_id":"s3","cwd":"'"$SANDBOX"'","transcript_path":""}'
check "a home-dir session still is" "$(count)" "1"
check "but is not named after your home folder" \
  "$(field "$(inbox | tail -1)" session)" "claude"
check "and does not become a project in the stats" \
  "$(field "$(inbox | tail -1)" folder)" ""

clear_inbox
fire done '{"session_id":"s4","cwd":"'"$PROJECT"'","transcript_path":""}'
check "a real project is named after its folder" \
  "$(field "$(inbox | tail -1)" session)" "my-app"
check "and groups under it" "$(field "$(inbox | tail -1)" folder)" "my-app"

# --------------------------------------------------------------------- exit

rm -rf "$SANDBOX"
printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
