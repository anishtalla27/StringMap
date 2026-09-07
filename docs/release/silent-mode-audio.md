# Silent-switch audio correction — build 2

The account holder reported that build 1 was audible only with the ringer enabled. Native AVAudioSession already used playback, but the alphaTab WKWebView did not set its Web Audio session type.

Build 2 sets navigator.audioSession.type to playback before constructing the synthesizer and again on play/resume. This shared bridge covers Tutorial Mode and Free Practice. Existing interruption, background and route-disconnection pause behavior is unchanged. Device media volume remains under user control.

Reference: https://bugs.webkit.org/show_bug.cgi?id=237322#c6

Verification: tutorial bridge checks pass, including configuration before synthesizer construction, restoring the session on resume, and compatibility without the API. Signed device Release build succeeds. Physical silent-switch audible confirmation remains pending; automated checks do not prove speaker output.

Build 1 is still selected in App Store Connect. Build 2 needs physical confirmation, archive validation, and replacement upload before submission.
