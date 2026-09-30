# StringMap promo video

`stringmap-promo.mp4` is a 26 second, 1920×1080, 30 fps ad for the StringMap iOS app. It cuts on every bar of the music: a hook, the brand, a fast product montage (lessons, Songbook, playback, practice tools), a quick look at the engine that picks each fingering, and an end card.

Every frame is drawn from real app material:

- The phone and iPad screens are the unaltered App Store screenshots from the `codex/native-ios-app` branch.
- The fretboard is redrawn from `FretboardView.swift`: same palette, same blended fret spacing (60% equal temperament, 40% linear), same red "now" and blue "next" markers.
- The soundtrack is the first 16 bars of Minuet in G from the app's Songbook (melody and chords arrangements, layered) at 132 BPM, played through the app's bundled CC0 guitar SoundFont. A synthesized kick on each downbeat and the SoundFont's own metronome click on beats two and three drive the pace.
- The fingering shown on screen is computed by `prep_data.py`, a Python port of `FingeringEngine.optimize` (candidate layers, forward DP, backtrack, backward suffix pass) using the Swift profile weights. The trellis, the `+4.7` rejected-route cost and the Beginner vs Balanced comparison come from that output, not from hand-placed numbers.

## Claims and where they come from

| On screen | Source |
| --- | --- |
| 24 lessons, 20 classics in Melody or Chords, tempo, loops | `docs/store/metadata.md` |
| Offline, no account, no ads, no tracking, Data Not Collected | `docs/store/metadata.md`, `docs/release/app-store-connect-status.md` |
| ~1.2 × 10^78 ways to play one song (Minuet in G, 126 notes) | `prep_data.py` over `minuet-g-melody.musicxml`, standard tuning, 20 frets |
| Finds the best one exactly, and shows why (+4.7 for fret 3) | `FingeringEngine.swift` (forward DP, `remainingCosts`, `makeDebugLayers`) |
| Five play styles | `Profiles.swift` |
| Chords on every string, four fingers with barres, whole hand shapes solved exactly | `PolyphonicOptimizer.swift` (`playableHand`) |
| 126 automated tests (77 core + 49 iOS) | `docs/release/songbook/README.md` |
| 196 audio tempo trials | `docs/release/songbook/README.md` |
| 3,108 sync checks | `docs/release/songbook/README.md`, `docs/tutorial-mode.md` |

Photo scanning and microphone listening are deliberately left out: neither ships in the release build.

The end card says "Free on iPhone and iPad" rather than "Available on the App Store" because the listing could not be confirmed as live when this was made. Swap the pill text in `sOutro` in `index.html` once it is.

## Rebuild

Needs Python 3 with `numpy` and `imageio-ffmpeg`, Node 20+, and Playwright with Chromium.

```bash
git worktree add ../stringmap-ios origin/codex/native-ios-app
export STRINGMAP_IOS=$(realpath ../stringmap-ios)
cd marketing/promo-video
./fetch_assets.sh                 # screenshots, icon, fonts
python3 prep_data.py              # parse the Songbook score, run the fingering engine port -> data.json
python3 render_soundtrack.py      # SoundFont render -> soundtrack.wav
node snap.mjs stills 1 9.4 16.2    # optional: stills at chosen seconds
node render.mjs stringmap-promo.mp4
```

Open `index.html?play` through any local web server to preview the animation live, or `index.html?t=11` for a single frame.
