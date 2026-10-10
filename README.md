# Luma Touch

A native macOS prototype for **Inclusive Learning for Everyone**: import a lesson,
read it with adjustable text, listen to speech, or explore short passages through
Morse patterns on a Force Touch trackpad. The interface uses translucent panels,
soft blue and peach layers, and a floating navigation dock.

## Run

Requires macOS 14 or newer and Apple Command Line Tools with Swift 6 or newer.
There are no third-party application dependencies.

```sh
bash scripts/build.sh
open "dist/Luma Touch.app"
```

The included two-page practice PDF opens automatically. Page one has selectable
text; page two is a raster scan to exercise on-device OCR. The app includes a
printable, single-page Morse alphabet sheet.

1. At the welcome screen, click the trackpad **three times quickly** to enter touch
   mode. The pointer is centered, held in the app and hidden. Press **Escape** to
   pause, restore it and use the standard interface. This selects an interaction
   preference; it does not diagnose or record a disability.
2. **Double-click** to start, pause or resume. Swipe **two fingers left/right** for
   the next/previous line, **up/down** for faster/slower, and secondary-click to
   replay. Each completed line waits for input. Navigation crosses page boundaries
   and skips empty pages. See the [complete controls and test guide](docs/Controls-Guide.md).
3. In the standard interface, open **Practice**. Rest a finger lightly on the trackpad and compare **Feel dot**
   with **Feel dash**. Playback starts after a short delay.
4. Try E, T, A, then HI. Use the Morse sheet from the dock or Help menu.
5. Open **Connections**, paste one provider key, select its card and test the connection.
6. Use **AI transcription** to transcribe a page or all remaining pages. This sends
   page images to the selected provider and may incur API charges.

## Draw to Ask AI

While reading in touch mode, **triple-click** to ask about the PDF. The ordinary
reader also has **Draw a question for AI** (Command–Shift–A). The pointer remains
hidden and fixed over the input surface throughout the question and reply.

- **Light one-finger tap:** dot. **Horizontal finger stroke:** dash. Lift after each.
- **Two-finger swipe right:** finish a letter. **Up:** finish a word/add a space.
- **Two-finger swipe left:** undo a mark, letter or space. **Down:** feel the draft.
- **Physically press the trackpad to click once:** send. A tap-to-click never sends;
  the app requires a Force Touch pressure event with the click. Return also sends.
- **Two-finger secondary click:** return to the same PDF position. Escape releases
  the pointer. Either action cancels a pending request and preserves the draft.

The app decodes Morse locally and uses the selected Gemini/OpenRouter/Groq key
only when sending. It includes the current line, up to 12,000 characters of the
current page, up to two matching page excerpts (4,000 characters each), and the
last two question/answer pairs. This is bounded text context, not the whole PDF
or its images. Source text is placed in a JSON data payload, separate from system
instructions. Provider errors do not expose raw responses or credentials.

Replies wait for a **double-click** to play in tactile Morse. Left/right swipes
advance/backtrack through reply lines, up/down change speed, **R** replays, and
**triple-click** starts a follow-up. Two-finger secondary click returns to the PDF.
Recognized marks and completed letters are echoed through the tactile player.
The draft is limited to 240 characters; new documents clear the conversation.
See [the test and gesture guide](docs/Controls-Guide.md#ask-ai-about-your-pdf).

## Providers and keys

Gemini, OpenRouter, and Groq each have a masked API-key field and an editable model
ID. Only the selected provider receives requests. Keys remain in memory unless
the user explicitly clicks **Save to Keychain**. **Forget** removes both the app's
in-memory value and its Keychain entry. No keys are placed in project files,
UserDefaults, logs, URLs, or bundled resources. Model preferences use UserDefaults.

Defaults checked against provider documentation on 2026-10-10:

| Provider | Default vision model | Protocol |
| --- | --- | --- |
| Gemini | `gemini-3.8-flash` | Google `generateContent` with inline image data |
| OpenRouter | `google/gemini-3.8-flash` | Chat completions with image content |
| Groq | `qwen/qwen3.8-27b` | Chat completions with image content |

The model must be available to the user's account and accept image input.
**Test connection verifies a small text request, not vision capability.** No live
provider calls were made during initial development because no user keys were supplied.

## Architecture

- **PDFReader**: PDFKit text extraction; fast English Vision OCR for pages with little
  embedded text. OCR has an eight-second deadline per page, with an explicit AI
  transcription fallback. Reads every page, rejects locked PDFs, and limits imports
  to 300 pages. Other scripts are best handled by the selected AI vision provider.
- **AIClient**: provider-specific request encoding, a fixed HTTPS endpoint per
  provider, ephemeral URLSession, checked responses and safe error messages.
  Truncated responses are rejected. AI instructions are kept separate from source
  content conceptually; no model output is executed or used as an app command.
- **Workspace**: document state, optional Keychain storage, cancellation, progress,
  page-at-a-time transcription and explicit network actions. Completed transcripts
  are preserved if a later page fails. Simplification is separate from the original.
- **Morse**: deterministic character lookup and standard 1/3/7 timing envelopes.
  Encoding and timeline calculation are O(n). No AI is needed for encoding.
- **HapticPlayer**: cancellable playback, speed, progress and distinct command cues.
  Uses public AppKit APIs. Dots request one short effect; dashes request a longer
  train of effects over a three-unit envelope.
- **TouchControlSurface / PointerCapture**: window-local native click, scroll and
  keyboard input; one command per physical swipe, with momentum ignored. Pointer
  capture is foreground-only and ends on Escape, focus loss or window changes.
  No global input hooks or Accessibility permission are needed. Reading uses
  nonempty source/OCR lines without arbitrary word-count splits.
- **MorseDrawingSurface / AskAIModel**: raw trackpad contact/stroke recognition,
  pressure-confirmed submission, local Morse decoding and editing, bounded PDF
  context, duplicate-request protection, cancellation and line-by-line replies.
- **SwiftUI**: reader, practice, provider settings, original-PDF preview, text export,
  keyboard actions, system accessibility labels, reduced-motion handling and a
  solid-surface option (also respects Reduce Transparency).

## Honest limits

The Mac trackpad does **not** provide raised-dot Braille, arbitrary motor waveforms,
or guaranteed haptic delivery. Dash playback is an approximation; it needs tactile
testing on the actual machine. This prototype has not been validated with deafblind
learners and is not a replacement for an established communication method.

Morse covers Latin letters, digits and common punctuation. Unsupported characters
are disclosed in the reader and skipped by the encoder; original text is retained.
Accents are folded and common typographic quotes/dashes normalized. The normal
reading pane remains available for other scripts. AI/OCR can misread complex layouts,
handwriting, diagrams and formulas; the original PDF is always available to compare.

Documents and transcripts are kept in memory. Export transcripts before closing;
document persistence and recovery are not implemented. The app is locally ad-hoc
signed, not notarized for distribution. Native VoiceOver labels are included, but
real VoiceOver/Braille-display and intended-user testing remain outstanding.

Touch mode operates a prepared lesson. Importing PDFs and entering API keys use
the standard interface, potentially with a helper. The learner needs prior
instruction in the gestures and tactile Morse; a visual welcome screen alone
cannot teach these to someone who cannot see or hear.

## Verification

```sh
bash scripts/test.sh
```

The standalone Swift test runner works without full Xcode/XCTest. It checks known
Morse vectors and gap timing; normalization and unsupported text; provider headers,
image payloads and secret placement; error/truncation handling; both practice PDF
pages, including OCR; playback cancellation; line/page boundaries; modal guards;
click sequences; and swipe direction/momentum. It makes no live API calls and
injects a silent haptic output for playback tests.

For an optional foreground pointer-lifecycle check, run
`bash scripts/test-pointer.sh --run-capture`. It briefly captures the pointer and
checks Escape, key-window changes, window movement and app deactivation, with a
12-second cleanup watchdog. Without `--run-capture`, it only builds and prints
instructions; it does not capture the pointer.

Run `"dist/Luma Touch.app/Contents/MacOS/LumaTouch" --verify-ui` from this project
directory to capture the app's own welcome/touch/reader/AI/practice/provider views into the ignored
`verification/` folder. This does not capture other applications or send requests.
It uses an explicitly labelled simulated AI reply and no saved keys, tests
touch-mode pointer capture, restores the pointer, then exits. Open the app normally
afterward to test with real input and your own provider key.

`scripts/make_practice_pdfs.py` regenerates the original practice PDFs using
ReportLab and pypdfium2. Generated PDFs are included, so Python is not needed to
build or use the application.

## References

- [Apple haptic feedback](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager)
- [Apple trackpad touch positions](https://developer.apple.com/documentation/appkit/nstouch/normalizedposition)
- [Apple pressure event information](https://developer.apple.com/documentation/appkit/nsevent/associatedeventsmask)
- [Google image understanding](https://ai.google.dev/gemini-api/docs/image-understanding)
- [OpenRouter multimodal inputs](https://openrouter.ai/docs/guides/overview/multimodal/images)
- [Groq vision](https://console.groq.com/docs/vision)
- [Morse I/O research](https://arxiv.org/abs/2205.04802)

The practice PDFs are original material. The app uses system fonts and SF Symbols;
it does not redistribute the pre-event asset library or reuse the external UI
preview's source code.

### Printed handwriting for communication

**Write to communicate** (Command–Shift–H) reuses the fixed-pointer raw trackpad
surface to collect multi-stroke printed letters. Swipe right to commit each letter,
up for a space, left to undo. A physical click renders a numbered JPEG letter grid
in memory and asks the selected image-capable provider to transcribe it. The model
must preserve one character per cell and explicit word spaces; malformed results
are rejected, uncertain characters are marked `?`, and drafts survive failures or
cancellation. No conversational answer is requested until a second deliberate click.
Swipe down reviews the transcription using the existing Morse player. This is
print-on-palm-inspired input, not tactile letter output. See the controls guide.

`HandwritingDraft` owns stroke bounds, pen lifts, editing and grid rendering;
`HandwritingPrompt` separates recognition instructions from image data and validates
response shape. Recognition is injected in tests and UI verification; passing those
checks does not establish real handwriting recognition accuracy or provider access.

### Handwriting chat (0.5)

Communication now uses a chat timeline with user and AI bubbles above the handwritten
message composer. Transcribe, review, then send; triple-click or press A after a reply
to write a follow-up. Fn–Up/Down browse the timeline and Command–Shift–N clears the
chat and cancels a pending request. History is session-only; the last two completed
exchanges are included in AI context. Existing Morse reply playback remains available.

### Android output (0.6)

Option–Z opens local pairing, then toggles the selected haptic output after Android
Chrome has enabled vibration. A QR/link in Connections opens a small receiver page.
`PhoneBridge` uses Network.framework HTTP/SSE on an ephemeral port, with a fresh
session token, bounded requests and heartbeat disconnection. Only numeric patterns
are transmitted. The receiver requires an explicit Enable action and stops when
hidden. HapticPlayer sends complete letters to preserve their internal timing; pause
cancels the phone pattern. No amplitude control or background/locked-screen guarantee.

`bash scripts/test-phone.sh` optionally verifies the real local HTTP/SSE transport in
Chrome using Playwright and mocked vibration hardware. Requires Node/Playwright and
Chrome at its standard macOS path. Core tests do not start a listener. Physical Android
vibration remains a manual test; browser acceptance is not motor confirmation.
