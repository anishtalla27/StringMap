(() => {
  "use strict";

  const post = (type, detail = {}) => {
    window.webkit?.messageHandlers?.stringMap?.postMessage({ type, ...detail });
  };

  const base = new URL(".", window.location.href);
  const api = new alphaTab.AlphaTabApi(document.getElementById("score"), {
    core: {
      scriptFile: new URL("alphaTab.min.js", base).href,
      fontDirectory: new URL("font/", base).href,
      useWorkers: true,
    },
    display: {
      staveProfile: alphaTab.StaveProfile.ScoreTab,
    },
    player: {
      // Avoid the automatic mode's score-dependent initialization. Creating the
      // synthesizer immediately lets WKWebView load the SoundFont before Swift
      // enables the transport controls.
      playerMode: alphaTab.PlayerMode.EnabledSynthesizer,
      // AudioWorklet startup does not complete reliably for a file-backed
      // WKWebView. alphaTab's ScriptProcessor output remains fully offline and
      // gives the iOS host a deterministic ready signal.
      outputMode: alphaTab.PlayerOutputMode.WebAudioScriptProcessor,
      soundFont: new URL("soundfont/sonivox.sf2", base).href,
      scrollElement: document.scrollingElement,
    },
  });

  api.renderFinished.on(() => post("rendered"));
  api.playerReady.on(() => post("playerReady"));
  api.soundFontLoad.on(({ loaded, total }) => post("soundFontLoad", { loaded, total }));
  api.playerStateChanged.on(({ state, stopped }) => post("playerState", { state, stopped }));
  api.playerPositionChanged.on(({ currentTime, endTime }) => post("position", { currentTime, endTime }));
  api.error.on((error) => post("error", { message: String(error) }));
  window.addEventListener("error", ({ message }) => post("error", { message }));
  window.addEventListener("unhandledrejection", ({ reason }) =>
    post("error", { message: String(reason) })
  );

  window.stringMap = {
    load(alphaTex) {
      api.tex(alphaTex);
    },
    playPause() {
      return api.playPause();
    },
    stop() {
      api.stop();
    },
    seek(milliseconds) {
      api.timePosition = Math.max(0, Number(milliseconds) || 0);
    },
    setSpeed(speed) {
      api.playbackSpeed = Math.min(2, Math.max(0.25, Number(speed) || 1));
    },
    setLoop(startTick, endTick) {
      const start = Math.max(0, Number(startTick) || 0);
      const end = Math.max(start + 1, Number(endTick) || 0);
      api.playbackRange = { startTick: start, endTick: end };
      api.isLooping = true;
    },
    clearLoop() {
      api.isLooping = false;
      api.playbackRange = null;
    },
    setMetronome(enabled) {
      api.metronomeVolume = enabled ? 0.75 : 0;
    },
    setCountIn(enabled) {
      api.countInVolume = enabled ? 0.75 : 0;
    },
  };

  post("bridgeReady");
})();
