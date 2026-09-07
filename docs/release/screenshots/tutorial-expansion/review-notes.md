# Visual comparison notes

Reviewed the beginning, middle and ending captures of **both examples in every lesson 13–24**. Contact sheets show the iPad in left-handed orientation. Slider positions are approximate UIKit seek locations, so a midpoint capture can still show the final event before a barline. Red markers are sounding notes; blue is the next position; gold marks authored A roots.

These contact sheets also retain defects found during review. The later transition/detail captures qualify the corrected panel height and barre-marker contrast; do not use the intermediate contact sheets as App Store assets.

| Lesson | Examples and comparison |
|---|---|
| 13 | Even pairs: open E4/B3 alternate on strings 1/2, eighth-note beams and down/up cues agree. Crossing current: the 0–1–3 fingering on string 2 and open/first/third frets on string 1 agree with the staff and tab. |
| 14 | Offbeat doorway starts and ends with silence; dotted quarters and shorter replies remain distinct. Across the barline shows one E tie and a parenthesized continuation tab number, followed by a rest and separately struck E notes. |
| 15 | Two groups shows six eighth notes, then two dotted quarters; C3 at 5/3, F3 at 4/3 and open G3 are correct. Drifting answer uses A3 at 3/2 and ends on C3 at 5/3 with a dotted half. Six-eight grouping and quarter-note BPM explanation are visible. |
| 16 | Three landing places uses string-1 frets 1–3–5–7 and returns to open E. Across the landing moves between strings 2 and 1 with third/fifth-position captions. The same fret can use a different prescribed finger after the shift; these labels agree with the authored hand position. |
| 17 | Ascending and descending fifth-position patterns cover all six strings. A2 is 6/5 with finger 1; C5 is 1/8 with finger 4. Gold A roots are on 6/5, 5/0, 4/7, 3/2 and 1/5 within the visible range. |
| 18 | Question and answer use the prescribed pentatonic positions. Rests clear the red sounding markers; sustained half/dotted notes and final A4 at 1/5 agree with the notation. |
| 19 | Em rings E2–G3–B3–E4; Am rings A2–A3–C4–E4. Separate strings remain lit through their durations. The latest pluck shows p/i/m/a rather than always p. The old panel cramped the lowest tab row: height increased after measuring every score. |
| 20 | D/Dm retain A3–D4 while F-sharp4 changes to F4; A/Am retain A3–E4 while C-sharp4 changes to C4. Three distinct strings, authored fingers and muted bass strings match the two triads in each score. |
| 21 | F uses A3–C4–F4 at 3/2, 2/1, 1/1 with a two-string index barre. The release example moves to open G3–B3–E4, with rests clearing the grip. The barre overlay reduced the contrast of the finger-1 labels; it was moved behind the markers. |
| 22 | Both strings show ascending 0→3 and 1→3 H connections in staff and tab. Resets/rests are separate from the connected pair; prescribed fingers and open circles agree. |
| 23 | Descending 3→1 P pairs and 1→3→1 H/P groups have the correct curves, direction, pitches and finger labels. Rests have no red sounding marker. |
| 24 | Lead study shows third-to-fifth position movement, A-minor pentatonic notes, H/P groups and a final rest. Ringing triads alternates D, Dm, A and Am twice, with the bass and upper notes on distinct strings. Review also checked that late measures follow the horizontal seek; the final build allows horizontal scrolling and has more vertical room for all voices. |

Written guitar pitches appear an octave above these sounding pitch names. Every event's numeric sounding MIDI, onset, duration and string/fret reconstruction is checked separately by Swift and synthesizer tests; visual review supplements those checks.

Direct CUA interaction with Simulator became stuck on a stale Window menu, while Xcode and XCTest remained usable. Screenshots were produced by real simulator UI interaction and reviewed visually; do not describe this as a completed human device listening session.

Final review also inspected all 69 authored transition captures in transitions-1 through transitions-5: every shift, triad change, barre action, H/P link and capstone chord change agrees with its prescribed position and hand cue. Final detail images show the corrected white barre finger numbers, red active staff/tab/chord highlights, and bar-eight cursor following a late capstone seek. Horizontal notation intentionally shows a viewport of the long study; it can scroll to the remaining notes.
