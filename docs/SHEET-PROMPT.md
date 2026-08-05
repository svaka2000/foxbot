# The one prompt

Attach `foxbot.png` (his current sprite) to the message, paste everything in the
block below, and send. You get back one image: a 3×3 sheet with all nine moods.

Then cut it up:

```bash
python3 tools/slice_sheet.py ~/Downloads/sheet.png
cp hammerspoon/foxbot/assets/*.png ~/.hammerspoon/foxbot/assets/
```

One image rather than nine requests is deliberate — everything is drawn in a
single pass, so the nine poses actually look like the same animal. Nine separate
generations drift.

---

```text
Attached is my pixel-art fox sprite. I'm building a sprite set for a desktop
app and I need nine more poses of THIS EXACT CHARACTER.

Give me ONE single image: a 3x3 grid containing nine poses of him.

=== LAYOUT ===
- Exactly nine poses, arranged 3 across and 3 down, in this order,
  left to right, top to bottom:

    1. WORKING      2. CONCENTRATING   3. ASKING
    4. PLEASED      5. CELEBRATING     6. ALARMED
    7. EXHAUSTED    8. DROWSY          9. ASLEEP

- Leave a clear, empty, evenly-sized gap between every pose, and a margin
  around the outside. The nine poses must never touch or overlap.
- Do NOT draw a grid, boxes, frames, borders, separators, labels, numbers,
  captions, titles, or any text anywhere in the image.
- Fully transparent background across the whole image. No scene, no ground,
  no shadows under the characters, no drop shadows, no glow.

=== KEEP IDENTICAL IN ALL NINE ===
- The same fox as the reference: same head shape, same ear shape and size,
  same muzzle, same body proportions, same straight-on front view, same
  sitting pose as the base.
- The same chunky pixel scale, and a thick unbroken dark outline all the way
  around every silhouette. Hard pixel edges — no anti-aliasing, no gradients,
  no blur, no soft shading.
- The same drawing size in every cell, so he doesn't grow or shrink between
  poses.
- ONLY these seven colours, no others anywhere in the image:
    #281E34  outline and eyes
    #161130  darkest accent
    #FC5900  fur
    #D84202  fur in shadow
    #FA8228  fur highlight
    #FEEDB6  cream
    #F7CA7A  cream in shadow

=== THE NINE POSES ===

1. WORKING — alert and busy. Leaning very slightly forward. Eyes wide, round
   and fully open with a bright cream catchlight in each. Both ears straight
   up and forward. Mouth a small open oval. Two very short cream motion
   dashes just behind each ear.

2. CONCENTRATING — deep in it. Sitting upright and still. Eyes narrowed to
   determined horizontal slits, not closed. A small dark angled notch above
   the inner edge of each eye, like a furrowed brow. Ears angled slightly
   back. Mouth a flat level line. One small cream sweat bead at the top
   right of his head. Focused, not distressed.

3. ASKING — waiting for you to answer. Whole head tilted noticeably to one
   side. Eyes wide, round and expectant, looking straight out. One ear
   straight up, the other flopped over at the tip. Mouth small and slightly
   open. One front paw raised in a small "excuse me" gesture. A cream
   question mark floating above and right of his head, drawn in the same
   chunky pixels with the same thick dark outline.

4. PLEASED — quietly satisfied. Same sitting pose as the reference. Both eyes
   closed in happy upward-curving arcs. Mouth a wide gentle closed smile.
   Ears upright and relaxed. Cheeks slightly fuller. Warm, not excited.

5. CELEBRATING — delighted. Both front paws raised above his head. Mouth wide
   open in a big grin with a cream tongue showing. Eyes closed in happy
   upward arcs. Ears straight up. Body lifted slightly as though caught
   mid-hop. Three small cream four-pointed sparkles around his head.

6. ALARMED — something just broke. Eyes wide and startled, large dark circles
   with small cream catchlights. Both ears pinned flat back against his head.
   Mouth a small open oval of surprise. Body pulled back, front paws lifted
   defensively. Fur bristling along his back and tail — small sharp spikes on
   the silhouette. A cream exclamation mark floating above his head, same
   chunky pixel style.

7. EXHAUSTED — end of a long day. Body slumped, shoulders lowered, head sunk
   slightly between them. Eyes half-lidded and tired, looking downward, small
   dark shadows beneath them. Both ears drooping down and outward. Mouth a
   small flat line. Tail limp along the ground. Worn out, not sad.

8. DROWSY — nodding off but still upright. Same sitting pose. Eyes half
   closed: a heavy lid over the top half of each, a sliver of dark pupil
   showing beneath. Head tilted slightly to one side. One ear upright, the
   other drooping outward. Mouth a small relaxed line. No z's — he's waiting,
   not asleep.

9. ASLEEP — properly out. Curled up: body lowered and rounded, head tipped
   down resting on his front paws, tail curled around his side. Both eyes
   closed as simple downward curves. Both ears relaxed and folded back and
   down. Mouth a small content closed line. ONE small cream "z" floating up
   and to the right of his head.

Every pose must still read clearly when shrunk to 96 pixels wide, so favour
bold shapes and strong contrast over fine detail.
```

---

## If it comes back wrong

**A grid, boxes or labels got drawn in.** Reply: *"Remove all grid lines, boxes,
borders and text. Just the nine characters on a transparent background with
empty space between them."*

**White or checkerboard background instead of transparent.** Reply: *"Redo it
with a solid flat magenta #FF00FF background, completely uniform, no other use
of magenta anywhere."* The slicer keys that out automatically.

**The poses touch or overlap.** Reply: *"Space them further apart — I need a
clear empty gap between all nine so I can cut them into separate files."*

**They drifted into different characters.** Reply with the reference attached
again: *"Keep the head, ears and body identical to the reference in all nine.
Change only the pose and the expression."*

**Colours went off.** Reply: *"Use ONLY these seven hex colours"* and paste the
list again. Generators drift warm; naming them twice usually fixes it.

**Fewer or more than nine.** Reply: *"Exactly nine poses, three rows of three,
in this order:"* and paste the list again.

## Checking before you commit to it

```bash
python3 tools/slice_sheet.py ~/Downloads/sheet.png --dry-run
```

That reports what it found without writing anything. Nine lines with sensible
sizes means the sheet is good. Warnings about falling back to even thirds mean
the gaps weren't clear enough — ask for more spacing and regenerate.
