# StringMap promo video

`stringmap-promo.mp4` is a 68 second, 1920×1080, 30 fps promotional video for the StringMap iOS app. It shows the product first (Tutorial Mode, Songbook, Play, offline and private) and then the engineering underneath.

Every frame is drawn from real app material:

- The phone and iPad screens are the unaltered App Store screenshots from the `codex/native-ios-app` branch.
- The fretboard is redrawn from `FretboardView.swift`: same palette, same blended fret spacing (60% equal temperament, 40% linear), same red "now" and blue "next" markers.
- The soundtrack is Minuet in G from the app's Songbook (melody and chords arrangements, layered), played through the app's bundled CC0 guitar SoundFont. Nothing else is in the mix.
- The fingering shown on screen is computed by `prep_data.py`, a Python port of `FingeringEngine.optimize` (candidate layers, forward DP, backtrack, backward suffix pass) using the Swift profile weights. The trellis, the `+4.7` rejected-route cost and the Beginner vs Balanced comparison come from that output, not from hand-placed numbers.

## Claims and where they come from

| On screen | Source |
| --- | --- |
| 24 lessons, 20 classics in Melody and Chords, 18 exercises | `docs/store/metadata.md` |
| Works offline, no account, Data Not Collected | `docs/store/metadata.md`, `docs/release/app-store-connect-status.md` |
| 126 notes, ~1.2 × 10^78 possible fingerings, 2,223 comparisons | `prep_data.py` over `minuet-g-melody.musicxml`, standard tuning, 20 frets |
| Exact DP, backward pass prices every alternative | `FingeringEngine.swift` (`remainingCosts`, `makeDebugLayers`) |
| Five profiles, all solved together | `Profiles.swift`, `AppModel.swift` (loops over `FingeringProfile.allCases`) |
| Chords as whole hand shapes, four fingers with barres, five-fret span, held notes stay put | `PolyphonicOptimizer.swift` (`playableHand`, edge constraints) |
| 126 automated tests (77 core + 49 iOS) | `docs/release/songbook/README.md` |
| 196 tempo trials rendered to audio | `docs/release/songbook/README.md` |
| 3,108 clock and seek checks | `docs/release/songbook/README.md`, `docs/tutorial-mode.md` |

Photo scanning and microphone listening are deliberately left out: neither ships in the release build.

The end card says "Free for iPhone and iPad" rather than "Available on the App Store" because the listing could not be confirmed as live when this was made. Swap the pill text in `sceneOutro` in `index.html` once it is.

## Rebuild

Needs Python 3 with `numpy` and `imageio-ffmpeg`, Node 20+, and Playwright with Chromium.

```bash
git worktree add ../stringmap-ios origin/codex/native-ios-app
export STRINGMAP_IOS=$(realpath ../stringmap-ios)
cd marketing/promo-video
./fetch_assets.sh                 # screenshots, icon, fonts
python3 prep_data.py              # parse the Songbook score, run the fingering engine port -> data.json
python3 render_soundtrack.py      # SoundFont render -> soundtrack.wav
node snap.mjs stills 5 38 60      # optional: stills at chosen seconds
node render.mjs stringmap-promo.mp4
```

Open `index.html?play` through any local web server to preview the animation live, or `index.html?t=38` for a single frame.
