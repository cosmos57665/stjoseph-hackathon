# Luma Touch — controls to try

Touch mode lets you control a prepared lesson without aiming at small buttons.
The practice PDF is included. Keep a finger lightly touching the Force Touch
trackpad while listening through touch.

## Start and finish

1. Open Luma Touch. Its welcome screen places the pointer over the app.
2. Click the trackpad **three times quickly** to enter touch mode. The pointer
   is hidden and held over the reading surface while this app is active.
3. Entry waits for you: double-click to start the selected line. A single click
   does not start or interrupt playback.
4. Press **Escape** to pause and leave touch mode. The pointer becomes usable
   again. Switching to another app also leaves touch mode and releases it.

Pressing Escape on the initial welcome screen opens the ordinary interface.
From the ordinary reader, **Command–Shift–T** enters touch mode again. PDF import,
API-key setup and other preparation use the ordinary interface outside touch
mode; this prototype does not make those tasks operable through Morse alone.

## Touch-mode controls

Directions below describe **your fingers' movement**, independent of macOS's
Natural scrolling setting. Move both fingers together for a swipe. One swipe
performs one command, even if the trackpad produces scrolling momentum.

| What you want | Trackpad control | Keyboard alternative |
| --- | --- | --- |
| Start, pause or resume the selected line | Double-click with one finger | Space |
| Move to the next line and play it | Swipe two fingers left | Right arrow |
| Move to the previous line and play it | Swipe two fingers right | Left arrow |
| Replay the current line from its first letter | Secondary click, usually a two-finger click | R |
| Make playback faster | Swipe two fingers up | Up arrow |
| Make playback slower | Swipe two fingers down | Down arrow |
| Pause and exit touch mode | — | Escape |
| Enter touch mode from the ordinary reader | Use the touch-mode control | Command–Shift–T |

A **click** means pressing the trackpad, not just resting or moving a finger.
If macOS Tap to click is enabled, its taps can produce the corresponding click
events. Two-finger replay follows your macOS Secondary click setting; **R** is
available regardless of that setting. Keyboard alternatives work with the touch
surface focused. Normal typing outside touch mode remains available.

## What playback does

- **One source line at a time.** Blank lines are skipped. A reading line is a
  trimmed line from the extracted PDF, OCR, transcript or pasted text; wrapping
  that text on screen does not create additional reading lines.
- **The end of a line waits for you.** Playback never starts the next line by
  itself. Swipe left when you want to continue.
- **Resume repeats the interrupted letter.** This gives you the complete pattern
  again after pausing halfway through a letter.
- **Next and previous begin playing the chosen line**, including when you were
  paused. They can cross PDF pages and skip pages with no readable text.
- **No silent wraparound.** At the first or last reading line, navigation stays
  at the boundary, pauses playback and gives an unavailable cue.
- **Replay starts this line again.** It does not reload the PDF or lose your page.
- **Speed changes repeat the current letter** if playback was running. At the
  fastest or slowest limit, the unavailable cue plays and reading pauses;
  double-click to continue at that speed.

Morse letters use short and longer pulse sequences. Control feedback uses the
following separate cues:

| Cue | Meaning |
| --- | --- |
| One soft tap | Ready, navigation, replay or speed change accepted |
| Two taps | Paused |
| Three spaced taps | The requested move is unavailable, such as a document boundary |

Finishing a line leaves silence: there is no extra Morse-like end pattern.
Playback starts after a short delay to separate the control cue from the text.
Trackpad haptics are approximations, so compare the actual feel on your Mac
rather than relying on the animation alone.

## A short test

For this exact sequence, leave touch mode and use **Paste your own text** to
prepare these three lines. The supplied PDF has different lines and can be used
for the separate page-navigation check below.

```text
HI
SOS
I AM SAM
```

1. Enter touch mode. Move your finger around: the pointer should remain hidden
   and you should not need to aim at a button.
2. Start **HI** with a double-click. H is four dots; I is two dots. After I,
   playback should stay silent: **SOS must not begin automatically**.
3. Swipe left once. **SOS** should begin. A long swipe must still advance only
   one line, even after your fingers lift.
4. Double-click during SOS to pause. Wait: there should be no ongoing Morse
   playback. Double-click again; the interrupted letter repeats in full.
5. Secondary-click or press **R**. SOS should restart at S.
6. Swipe up, then down, and compare the playback speed. These gestures should
   not move between lines.
7. Swipe right to HI, then right again. It should stay at the first line and
   signal the boundary. Try the same beyond the final line in the other direction.
8. Press Escape. Confirm the pointer is visible and moves normally. Re-enter,
   then switch to another app with Command–Tab; pointer movement should again
   work normally, and Luma's Morse playback should be paused.
9. Outside touch mode, open the text-entry or Connections interface and type.
   Spaces, R and arrow keys should behave as ordinary text controls there.

For a PDF-specific check, move from the last readable line of one page to the
next: the next page's first readable line should play. Move back to confirm the
previous page's last line is selected. Use the visible page/line labels while
testing the controls.

## Other useful controls

| Control | Purpose |
| --- | --- |
| Import a PDF / Command–O | Choose a PDF through the macOS file picker |
| Paste your own text | Prepare a short lesson without a PDF or API key |
| Practice → Feel dot / Feel dash | Compare the two Morse marks |
| Morse sheet | Open the printable alphabet reference |
| Connections | Add a Gemini, OpenRouter or Groq key and test the provider |
| Escape from touch mode | Return to the ordinary reader and setup controls |

The controls can be tested without an API key. Live AI transcription requires a
working provider key. Independent use, gesture comfort and cue distinguishability
still need testing with the intended learners.
