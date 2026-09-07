# Manual visual fretboard check — build 3

September 6, 2026. Current Release build, iPad Pro 13-inch (M5) simulator, iOS 26.5. Operated the public UI through Simulator accessibility controls and visually inspected screenshots while playing and paused. This is separate from the earlier automated physical-iPhone clock test.

## Sampled harder bundled pieces

| Piece | Visually observed agreement |
| --- | --- |
| Chromatic Neighbors (68 BPM) | Playing E3/string 4 fret 2, F3/string 4 fret 3, and paused G3/string 3 open and E3/string 4 fret 2 matched the staff cursor and corresponding tab positions. Sharp and natural notation was visible. |
| D Major Turn (80 BPM) | Playing F-sharp3/string 4 fret 4 matched the F in the two-sharp staff and tab 4 on string 4. Paused measure 3 E3/string 4 fret 2 also matched. Initial D3/string 5 fret 5 is a valid alternate position. |
| Small Journey (84 BPM) | Playing eighth-note G3/string 3 open matched the red staff note and tab 0. Paused measure 3 F3/string 4 fret 3 matched the score/tab cursor. Mixed eighth and dotted rhythms and rests render clearly. |
| Six Eight Drift (72 BPM) | Playing A3/string 3 fret 2 matched the fourth eighth-note staff/tab highlight. Paused measure 3 E3/string 4 fret 2 matched the cursor and tab 2. Both beamed eighths and dotted held notes render clearly. |

Cross-check: standard guitar open strings in sounding MIDI are 64, 59, 55, 50, 45, 40 for strings 1–6. Therefore D3 = 45+5=50; E3 = 50+2=52; F3 = 50+3=53; F-sharp3 = 50+4=54; G3 = 55+0=55; A3 = 55+2=57. These agree with the independent exercise catalog events inspected during this run. Guitar staff pitches display one octave above these sounding pitches.

Result: no note-position mismatch or frozen cursor found in the sampled passages. Playback visibly moved between notes, updated the red current/blue upcoming fret markers, and paused on the corresponding score position. Four pieces were sampled; this is not a claim to have manually checked every event in all 18 pieces, every tempo, or physical audio.

Retained native screenshots:
- artifacts/manual-fretboard-build3/chromatic-e3.png
- artifacts/manual-fretboard-build3/small-journey-f3.png
- artifacts/manual-fretboard-build3/six-eight-e3.png

Additional live playback screenshots, including D-major F-sharp, are in the task's computer-use outputs. No product code changed. Simulator coordinate dragging failed in the control tool; AX value assignment moved only the slider widget, so it was not counted as a successful seeking test. Restart and ordinary Play/Pause were then used for the visual comparisons.
