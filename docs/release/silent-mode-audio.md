# Playback audio correction — build 3

Build 1 was audible only with the ringer enabled. Build 2 configured WebKit's audio session for playback, but left an exclusive native AVAudioSession activation before every Play. The user then reported a stationary cursor with no note highlighting.

The physical iPhone regression test reproduced build 2's frozen playback: the Lesson position did not change within 12 seconds. Build 3 removes the competing native session activation. WebKit owns the synthesizer session, configured for playback before synthesis and restored only when its type changes. Existing interruption, background and headphone-disconnection pause handling remains.

Evidence on iPhone 14 Pro / iOS 26.6.1:
- artifacts/build2-clock-reproduction.xcresult: FAIL, playback clock did not advance.
- artifacts/build3-clock-regression.xcresult: PASS, tutorial clock advances and resumes after pause.
- artifacts/build3-playback-and-highlights.xcresult: PASS, tutorial and Free Practice playback positions advance and active fretboard-note values change; tutorial pause/resume also passes.
- JavaScript bridge checks and signed Release content audit pass.

Physical audible output with the silent switch on still requires human confirmation. Media volume remains under user control. Build 1 remains selected in App Store Connect; build 3 must replace it after qualification. Neither build 1 nor build 2 should be submitted.

WebKit audio-session reference: https://bugs.webkit.org/show_bug.cgi?id=237322#c6
