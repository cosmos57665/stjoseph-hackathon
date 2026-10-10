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

1. Open **Practice**. Rest a finger lightly on the trackpad and compare **Feel dot**
   with **Feel dash**. Playback starts after a short delay.
2. Try E, T, A, then HI. Use the Morse sheet from the dock or Help menu.
3. In **Reader**, choose a short passage and press Play. Pause repeats the current
   letter when resumed. Previous/next skips words. Restart returns to the beginning.
4. Open **Connections**, paste one provider key, select its card and test the connection.
5. Use **AI transcription** to transcribe a page or all remaining pages. This sends
   page images to the selected provider and may incur API charges.

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
- **HapticPlayer**: cancellable playback, word navigation, speed and progress.
  Uses public AppKit APIs. Dots request one short effect; dashes request a longer
  train of effects over a three-unit envelope.
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

## Verification

```sh
bash scripts/test.sh
```

The standalone Swift test runner works without full Xcode/XCTest. It checks known
Morse vectors and gap timing; normalization and unsupported text; provider headers,
image payloads and secret placement; error/truncation handling; both practice PDF
pages, including OCR; and player navigation/reset. It makes no live API calls.

Run `dist/Luma Touch.app/Contents/MacOS/LumaTouch --verify-ui` from this project
directory to capture the app's own reader/practice/provider views into the ignored
`verification/` folder. This does not capture other applications or send requests.

`scripts/make_practice_pdfs.py` regenerates the original practice PDFs using
ReportLab and pypdfium2. Generated PDFs are included, so Python is not needed to
build or use the application.

## References

- [Apple haptic feedback](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager)
- [Google image understanding](https://ai.google.dev/gemini-api/docs/image-understanding)
- [OpenRouter multimodal inputs](https://openrouter.ai/docs/guides/overview/multimodal/images)
- [Groq vision](https://console.groq.com/docs/vision)
- [Morse I/O research](https://arxiv.org/abs/2205.04802)

The practice PDFs are original material. The app uses system fonts and SF Symbols;
it does not redistribute the pre-event asset library or reuse the external UI
preview's source code.
