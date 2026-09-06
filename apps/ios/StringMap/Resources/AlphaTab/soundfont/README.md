# StringMap classical guitar SoundFont

Based on FreePats **Spanish classical guitar, version 2019-06-18**, recorded by Roberto <roberto@zenvoid.org> in 2008 using an AKG Perception 120 microphone. Samples were filtered and processed by their creator. Source: https://freepats.zenvoid.org/Guitar/acoustic-guitar.html .

The creator dedicates the recordings and bank to the public domain under **CC0 1.0**. The complete dedication is in `LICENSE`. StringMap also dedicates its original metronome click and bank adaptation to CC0 1.0.

No SONiVOX or Creative-bank samples are included. Guitar PCM is unchanged from the pinned source. A 10 dB preset attenuation reserves headroom for simultaneous strings; six-string chords at maximum MIDI velocity are checked for clipping. `scripts/build-guitar-soundfont.py` adds General MIDI nylon program 24, program 25 for older saved scores, and an original 60 ms synthesized metronome click on percussion key 33. Edge sample zones extend across MIDI 0–127 for notation audition, with resampling; the normal tested guitar range is MIDI 36–88. Natural sample tuning is within 18 cents of equal temperament across that tested range. Physical device listening remains part of release QA.

Reproduction: download `SpanishClassicalGuitar-SF2-20190618.7z` from the source page, extract it, and run the build script with its `SpanishClassicalGuitar-20190618.sf2` path. The script rejects a different source checksum.

- Download SHA-256: `8c192f1fc640a553199a4a43a17ae12354a6a05e3d6aad79bd43b5d29314ff51`
- Original SF2 SHA-256: `0d4c08ea8c1c8924b3829084b0c8778f6d6b906f331e44fde51bc159f76b03b9`
- Bundled SF2 SHA-256: `c5aaed6f4e1782ae11a6c783a92c9522d32b46bb8c6828afc7bb4db32e8a9ec5`

`node scripts/verify-soundfont.mjs` renders actual PCM using the bundled alphaTab synthesizer, checking finite, non-silent guitar samples, compatibility program 25, and metronome audio. This is synthesis evidence, not a physical speaker/Bluetooth test.
