"""Generate the original practice lesson and a grayscale-safe Morse reference."""
from pathlib import Path
from io import BytesIO
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.colors import HexColor, white
from reportlab.lib.utils import ImageReader
import pypdfium2 as pdfium

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs"
OUT.mkdir(exist_ok=True)
W, H = A4
INK = HexColor("#20334a")
MUTED = HexColor("#556273")
PALE = HexColor("#eef2f6")
ALPHABET = dict(zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", [
    ".-", "-...", "-.-.", "-..", ".", "..-.", "--.", "....", "..", ".---", "-.-", ".-..", "--", "-.", "---", ".--.", "--.-", ".-.", "...", "-", "..-", "...-", ".--", "-..-", "-.--", "--..", "-----", ".----", "..---", "...--", "....-", ".....", "-....", "--...", "---..", "----."
]))

def text(c, x, y, value, size=12, bold=False, color=INK):
    c.setFillColor(color)
    c.setFont("Helvetica-Bold" if bold else "Helvetica", size)
    c.drawString(x, y, value)

def marks(c, x, y, code, unit=4):
    c.setFillColor(INK)
    for mark in code:
        if mark == ".":
            c.circle(x + unit / 2, y + unit / 2, unit / 2, fill=1, stroke=0)
            x += unit * 1.8
        else:
            c.roundRect(x, y, unit * 2.8, unit, unit / 2, fill=1, stroke=0)
            x += unit * 3.6
    return x

def footer(c, page, subtitle):
    c.setStrokeColor(HexColor("#cad2db"))
    c.line(42, 53, W - 42, 53)
    text(c, 42, 36, "LUMA TOUCH  /  " + subtitle, 8, color=MUTED)
    text(c, W - 52, 36, str(page), 8, color=MUTED)

# Two-page practice PDF: one native-text page and one scanned page.
c = canvas.Canvas(str(OUT / "Start-Here-Practice.pdf"), pagesize=A4)
c.setTitle("Luma Touch - First practice lesson")
c.setAuthor("Luma Touch")
text(c, 45, H - 90, "HI", 52, True)
text(c, 45, H - 125, "A small word. A new way to learn.", 17)
text(c, 45, H - 195, "I AM SAM.", 23, True)
text(c, 45, H - 235, "I CAN LEARN.", 23, True)
text(c, 45, H - 275, "ONE LETTER AT A TIME.", 23, True)
c.setFillColor(PALE)
c.roundRect(42, H - 480, W - 84, 145, 15, fill=1, stroke=0)
text(c, 60, H - 368, "A tiny science lesson", 18, True)
for y, line in enumerate([
    "Plants need sunlight and water to grow.",
    "Leaves use light to help make food.",
    "Plants release oxygen into the air."
]): text(c, 60, H - 402 - y * 24, line, 16)
text(c, 45, 235, "Try it in Luma Touch", 16, True)
for y, line in enumerate([
    "1. In Practice, feel E (dot) and T (dash).",
    "2. Return to Reader. Choose a short passage.",
    "3. Rest a finger on the trackpad, then press Play.",
    "4. Use the Morse sheet to decode each letter."
]): text(c, 45, 204 - y * 25, line, 12)
footer(c, 1, "SELECTABLE TEXT / ORIGINAL PRACTICE MATERIAL")
c.showPage()

scan = BytesIO()
s = canvas.Canvas(scan, pagesize=A4)
text(s, 45, H - 70, "SUNLIGHT TO FOOD", 29, True)
text(s, 45, H - 108, "A scanned-page practice lesson", 15, color=MUTED)
for y, line in enumerate([
    "Green leaves contain chlorophyll.",
    "Plants use sunlight, water and carbon dioxide",
    "to make glucose. Oxygen is released.",
    "This process is called photosynthesis."
]): text(s, 45, H - 175 - y * 28, line, 16)
for x, label in [(45, "SUNLIGHT"), (225, "LEAF"), (405, "FOOD")]:
    s.setFillColor(PALE)
    s.roundRect(x, 340, 140, 90, 15, fill=1, stroke=0)
    text(s, x + 20, 382, label, 14, True)
for x in [191, 371]:
    s.setStrokeColor(INK)
    s.line(x, 385, x + 26, 385)
    s.line(x + 26, 385, x + 19, 391)
    s.line(x + 26, 385, x + 19, 379)
text(s, 45, 283, "Check your understanding", 18, True)
text(s, 45, 248, "What gas do plants release?", 16)
text(s, 45, 217, "Answer: oxygen.", 16)
text(s, 45, 135, "This page is an image: on-device OCR reads its text.", 11, color=MUTED)
text(s, 45, 116, "AI transcription can also describe the simple diagram.", 11, color=MUTED)
footer(s, 2, "SCANNED PAGE / ORIGINAL PRACTICE MATERIAL")
s.save()
doc = pdfium.PdfDocument(scan.getvalue())
bitmap = doc[0].render(scale=2)
c.drawImage(ImageReader(bitmap.to_pil()), 0, 0, width=W, height=H)
c.showPage()
c.save()

# One-page reference. All marks are vector shapes, avoiding font glyph failures.
c = canvas.Canvas(str(OUT / "Morse-Reference.pdf"), pagesize=A4)
c.setTitle("Morse Code - A pocket guide to feeling letters")
c.setAuthor("Luma Touch")
text(c, 42, H - 44, "LUMA TOUCH / YOUR FIRST REFERENCE", 9, True, MUTED)
text(c, 42, H - 83, "A little guide to Morse.", 29, True)
text(c, 42, H - 109, "Letters become patterns. Patterns become words.", 12, color=MUTED)
c.setFillColor(PALE)
c.roundRect(42, H - 193, W - 84, 63, 12, fill=1, stroke=0)
marks(c, 58, H - 159, ".", 8)
text(c, 80, H - 158, "DOT = 1 time unit", 11, True)
marks(c, 296, H - 159, "-", 8)
text(c, 331, H - 158, "DASH = 3 time units", 11, True)
text(c, 58, H - 179, "Pauses: 1 unit within a letter / 3 between letters / 7 between words", 10)

items = list(ALPHABET.items())
col_width = (W - 84) / 4
for index, (letter, code) in enumerate(items):
    col, row = divmod(index, 9)
    x = 42 + col * col_width
    y = H - 228 - row * 36
    if row % 2 == 0:
        c.setFillColor(HexColor("#f2f4f6"))
        c.roundRect(x, y - 10, col_width - 6, 31, 5, fill=1, stroke=0)
    text(c, x + 10, y, letter, 17, True)
    marks(c, x + 36, y + 4, code, 4)

text(c, 42, 265, "Start with these", 17, True)
for y, word, explanation in [(236, "E", "one dot"), (211, "T", "one dash"), (186, "HI", "H = four dots, I = two dots"), (161, "SOS", "three dots / three dashes / three dots")]:
    text(c, 42, y, word, 13, True)
    x = 91
    for letter in word:
        x = marks(c, x, y + 2, ALPHABET[letter], 4.5) + 14
    text(c, 280, y, explanation, 10, color=MUTED)

text(c, 42, 115, "How it feels on your Mac", 12, True)
text(c, 42, 97, "Dot: a short tap. Dash: a longer train of taps, approximating three units.", 10)
text(c, 42, 81, "Keep a finger on the trackpad. This is an experimental Morse aid, not Braille.", 10)
footer(c, 1, "PRINT AT 100% / BLACK-AND-WHITE FRIENDLY")
c.save()

# Render the actual output pages for visual verification.
verify = ROOT / "verification"
verify.mkdir(exist_ok=True)
for filename in ["Start-Here-Practice", "Morse-Reference"]:
    doc = pdfium.PdfDocument(str(OUT / (filename + ".pdf")))
    for i in range(len(doc)):
        doc[i].render(scale=1.5).to_pil().save(verify / f"{filename}-{i+1}.png")
print("Created two-page practice PDF and one-page Morse reference; rendered all three pages.")
