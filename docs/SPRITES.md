# Drawing the rest of the fox

Foxbot has ten moods. Each can have its own drawing; any that doesn't falls back
to the default, so you can add them one at a time and nothing breaks.

Name the files after the coat and the mood:

```
foxbot.png             the default — you already have this
foxbot-sleeping.png    small hours, nothing running
foxbot-dozing.png      you're away from the machine
foxbot-running.png     a turn is underway
foxbot-focused.png     a turn has been going 5+ minutes
foxbot-asking.png      something is blocked on you
foxbot-settled.png     a turn just landed
foxbot-cheering.png    25 turns in a day
foxbot-weary.png       3+ hours of work behind you, nothing running
foxbot-broken.png      something failed
```

Drop them in `~/.hammerspoon/foxbot/assets/`, then run each one through the
importer so the edges stay hard at 96 points:

```bash
python3 tools/import_sprite.py ~/Downloads/whatever.png --name foxbot-sleeping
```

**Sprite ▸ Moods with their own art** in his menu shows which ones you've done.

---

## Before you start

Two things matter more than the prompt itself:

1. **Attach the original `foxbot.png` to every request** and say it's the
   reference. Describing a character from scratch each time gets you ten
   different foxes.
2. **Change one thing at a time.** Every prompt below says explicitly what must
   *not* change. That's the part that keeps the set looking like one animal.

## The style contract

Paste this **above** every mood prompt, with the reference image attached.

```text
Here is my existing pixel-art fox sprite. I need another pose of the SAME
character for an animated sprite set. Match it exactly.

MUST NOT CHANGE:
- The same fox: same head shape, same ear shape and size, same body
  proportions, same sitting pose and camera angle (straight-on front view).
- The exact palette, no other colours at all:
    outline / eyes   #281E34
    darkest accent   #161130
    fur              #FC5900
    fur in shadow    #D84202
    fur highlight    #FA8228
    cream            #FEEDB6
    cream in shadow  #F7CA7A
- The same chunky pixel scale and the same thick, unbroken dark outline all
  the way around the silhouette.
- The same overall size and framing, so the character does not appear to
  grow, shrink or shift between poses.
- Fully transparent background. No scene, no ground shadow, no drop shadow,
  no glow, no frame, no border, no text, no watermark.

MUST READ AT 96 PIXELS WIDE — bold shapes, strong contrast, no fine detail.

WHAT TO CHANGE:
<paste one of the mood blocks below>
```

---

## The moods

### Sleeping — the small hours, nothing running

```text
WHAT TO CHANGE:
He is fast asleep. Curl him up: body lowered and rounded, head tipped down
and resting against his front paws, tail curled around the side of his body.
Both eyes closed, drawn as simple downward curved lines. Both ears relaxed
and folded slightly back and down. Mouth a small closed line, content.
Add one small cream "z" floating up and to the right of his head — a single
z, small enough to read as a detail, not a speech bubble.
```

### Dozing — you're away from the machine

```text
WHAT TO CHANGE:
He is dozing, but not properly asleep. Keep him sitting upright in the
original pose. Eyes half-closed: the top half of each eye covered by a
heavy lid, a sliver of dark pupil showing beneath. Head tilted slightly to
one side. One ear upright, the other drooping outward. Mouth a small
relaxed line. No z's — he is waiting, not sleeping.
```

### Running — a turn is underway

```text
WHAT TO CHANGE:
He is alert and working. Keep him sitting, but lean the upper body very
slightly forward. Eyes wide and round, fully open, pupils large, with a
bright cream catchlight in each. Both ears straight up and forward,
attentive. Mouth a small open oval, focused. Add two very short horizontal
cream motion lines just behind each ear, suggesting quick movement — thin,
two or three pixels each, not a blur.
```

### Focused — five minutes in and still going

```text
WHAT TO CHANGE:
He is deep in concentration. Keep him sitting upright and still. Eyes
narrowed into determined horizontal slits — thick dark bars with a thin
cream highlight, not closed. Brow furrowed: a small dark angled notch above
the inner edge of each eye. Both ears angled slightly back. Mouth a flat,
level line. Add one small cream sweat bead at the top right of his head.
Calm and locked in, not distressed.
```

### Asking — something is blocked on you

```text
WHAT TO CHANGE:
He is asking you a question and waiting for an answer. Tilt his whole head
noticeably to one side. Eyes wide, round and expectant, looking straight at
the viewer, catchlight in each. One ear straight up, the other flopped over
at the tip. Mouth small and slightly open. Raise one front paw off the
ground in a small "excuse me" gesture. Add a cream question mark floating
above and to the right of his head, drawn in the same chunky pixel style
and thick dark outline as the character.
```

### Settled — a turn just landed

```text
WHAT TO CHANGE:
He is quietly pleased. Keep the original sitting pose. Both eyes closed in
a happy curve — arcs bending upward like ^ ^. Mouth a wide, gentle closed
smile. Both ears upright and relaxed. Cheeks slightly fuller. Warm and
content, not excited.
```

### Cheering — twenty-five turns in a day

```text
WHAT TO CHANGE:
He is delighted with himself. Both front paws raised up above his head in
celebration. Mouth wide open in a big happy grin showing a cream tongue.
Eyes closed in upward-curving happy arcs. Both ears straight up. Lift the
whole body very slightly, as though caught mid-hop. Add three small cream
four-pointed sparkles around his head — one upper left, one upper right,
one to the right — in the same chunky pixel style.
```

### Weary — a long day behind you

```text
WHAT TO CHANGE:
He is worn out. Slump the body: shoulders lowered, head sunk down slightly
between them. Eyes half-lidded and tired, looking downward, with small dark
shadows beneath. Both ears drooping down and outward. Mouth a small flat
line. Tail limp along the ground rather than curled. Tired but not sad —
the look of an animal at the end of a long shift.
```

### Broken — something failed

```text
WHAT TO CHANGE:
He is alarmed. Eyes wide open and startled — large dark circles with small
cream catchlights, whites showing. Both ears pinned flat back against his
head. Mouth a small open oval of surprise. Body pulled back and slightly
away, front paws lifted defensively off the ground. Fur on the back and
tail bristling: add small sharp spikes along the silhouette edge. Add one
small cream exclamation mark floating above his head, in the same chunky
pixel style with a thick dark outline.
```

---

## After you generate them

Run each through the importer. Generators return "pixel art" that was rendered
at high resolution with soft edges and tens of thousands of colours, which turns
to mush at 96 points. The importer crops to the artwork, drops the halo left by
the keyed-out background, snaps every pixel to the seven-colour palette above,
and writes at twice display size so it stays sharp on a Retina screen.

```bash
for m in sleeping dozing running focused asking settled cheering weary broken; do
  python3 tools/import_sprite.py ~/Downloads/fox-$m.png --name foxbot-$m
done
```

Then copy them across and reload:

```bash
cp hammerspoon/foxbot/assets/*.png ~/.hammerspoon/foxbot/assets/
```

## If one comes out wrong

- **Wrong colours.** Say "use ONLY these seven hex colours" and list them again.
  Generators drift warm; naming the hexes twice helps.
- **Soft or blurry.** Add "hard pixel edges, no anti-aliasing, no gradients, no
  blur" — then run the importer anyway, which fixes it regardless.
- **Grey checkerboard in the image.** It has drawn transparency rather than
  using it. Re-run with "solid flat magenta #FF00FF background, completely
  uniform" and the importer will key it out.
- **Character drifted.** Attach the reference again and add "keep the head and
  ears identical to the reference, change only the pose and expression".
- **Different size to the others.** Ask for "the same framing and scale as the
  reference image".
