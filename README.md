# Swatch Monster

A native Apple Silicon color picker for macOS, built to replace ColorSnapper 2
(x86_64-only, unmaintained since 2017, surviving on Rosetta).

Written from scratch. No ColorSnapper code or assets are used.

## Features

- Global hotkeys, carried over from ColorSnapper 2:
  - `⌃⌥⌘C` — pick a color anywhere on screen
  - `⌃⌥⌘X` — open the library window
- System loupe (`NSColorSampler`), so the magnifier always matches current macOS
- Menu-bar panel with hero swatch, history, and pinned colors
- Formats: Hex, Hex uppercase, RGB, RGBA, HSL, **CMYK**, SwiftUI `Color`,
  `NSColor`, `UIColor`
- WCAG 2.1 contrast ratios against white and black, with AA/AAA grading
- **Nearest named color** from any loaded swatch book, scored with CIEDE2000
- Launch at login

## Color names

The panel names the current color from the 31,914-entry
[meodai/color-names](https://github.com/meodai/color-names) list — the same data
behind colornamer.robertcooper.me. Closest name plus two alternates; click any
to copy the name. Matched with CIEDE2000, so top hits usually land under ΔE 1.

Loaded off the main thread at launch (~60ms) and cached per color (~5ms/lookup).

Names are evocative labels, not print references — deliberately kept separate
from the swatch books in `Palettes/`.

## Pairings

The menu-bar panel shows harmonies and a tone ramp derived from the current
color: complement, split, analogous, triad, tetrad, plus a 9-step ramp. Click
any chip to copy it; right-click to pin it.

Hue rotation happens in **LCh** (polar Lab), not HSL, so a set holds together
perceptually. Rotating `#fcd300` by 180° gives `#bfd8ff` in LCh at identical
lightness; HSL gives `#00157e` — 70 points of lightness darker, which is not a
complement of anything. Generated colors are gamut-mapped by pulling chroma in
until they fit sRGB, since clamping channels would shift the hue.

The ramp tapers chroma toward both ends, because holding it flat makes the
extremes look neon rather than like a hand-built ramp.

## Swatch cards

Library window > select a color > **Copy Card** (PNG to the clipboard, for Slack)
or **Export Card…** (PNG or PDF to disk). Optional name field titles the card;
without one the hex carries it.

One renderer draws into any `CGContext`, so PNG and PDF come from identical
drawing code. PDF is vector at 460×620pt.

Derived values are labelled on the card itself — `CMYK — derived`, and any
nearest-match line reads `reference only, not a print spec`. A card is a
reference artifact, never a print specification.

## Color accuracy

- Colors are stored in **sRGB**, so hex is stable across displays.
- **CMYK** goes through ColorSync's Generic CMYK profile — a real colorimetric
  conversion, not `1 - max(r,g,b)`. It is *not* your press profile; verify
  against the real output profile before sending to print.
- **Matching** uses CIEDE2000 in CIELAB (D65). Rough reading of ΔE:
  under 1 imperceptible, under 2 very close, under 5 close, above 10 poor.

## Swatch books

Books live in `~/Library/Application Support/Swatch Monster/Palettes/`.

| Format | Notes |
|--------|-------|
| `.acb` | Adobe Color Book — what Illustrator and Photoshop ship |
| `.ase` | Adobe Swatch Exchange — Swatches panel > Save Swatch Library as ASE |
| `.csv` | `name,hex` per line, no header |

**Settings > Palettes > Import Adobe Books** copies the books already installed
with your Adobe apps. On this machine that is 14 books / 7,373 colors:
TRUMATCH, TOYO, DIC, HKS, FOCOLTONE, ANPA.

### Pantone

Not included. Pantone's libraries are licensed and cannot be redistributed, and
Adobe removed its bundled Pantone books from Creative Cloud in 2022 — so they
are not on this Mac either. To match against Pantone, supply the data yourself
from a source you're licensed for:

- Pantone Connect (Adobe plugin or web app) — export swatches, save as `.ase`
- An older pre-2022 Adobe install — copy its `PANTONE*.acb` files
- A physical guide plus a hand-built `.csv`

Drop the file in the palettes folder and hit Reload.

## Building

Requires only the Command Line Tools — no Xcode, no Homebrew.

```sh
./build.sh          # build into ./build
./build.sh install  # build, install to /Applications, relaunch
./tools/makeicon.sh # regenerate the icon
```

To use your own icon art, put a 1024×1024 PNG at `tools/icon-source.png` and
rerun `makeicon.sh`.

## Credits

Color names: [meodai/color-names](https://github.com/meodai/color-names) — MIT
licence, © 2017 David Aerne. Full licence bundled at
`Resources/colornames-LICENSE.txt`.

## Known limits

- Hotkeys are fixed in this version; there's no recorder UI yet.
- Ad-hoc signed, so it runs here but isn't notarized for distribution.
- The loupe is Apple's, not a custom magnifier — no scroll-to-zoom or
  arrow-key nudging.
