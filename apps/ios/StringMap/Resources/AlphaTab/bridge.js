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
      soundFont: new URL("soundfont/stringmap-guitar.sf2", base).href,
      scrollElement: document.scrollingElement,
    },
  });

  let sourceNotes = [];
  api.scoreLoaded.on(score => {
    if (sourceNotes.length) globalThis.StringMapSourceMap.assign(score, sourceNotes);
  });
  api.renderFinished.on(() => post("rendered"));
  api.playerReady.on(() => post("playerReady"));
  api.soundFontLoad.on(({ loaded, total }) => post("soundFontLoad", { loaded, total }));
  api.playerStateChanged.on(({ state, stopped }) => post("playerState", { state, stopped }));
  // alphaTab reports speed-adjusted milliseconds. Swift stores score-time
  // milliseconds so seeking, note identities and the fretboard share one clock.
  api.playerPositionChanged.on(({ currentTime, endTime, originalTempo, modifiedTempo }) => {
    const speed = originalTempo > 0 ? modifiedTempo / originalTempo : api.playbackSpeed;
    post("position", { currentTime: currentTime * speed, endTime: endTime * speed });
  });
  api.error.on((error) => post("error", { message: String(error) }));
  window.addEventListener("error", ({ message }) => post("error", { message }));
  window.addEventListener("unhandledrejection", ({ reason }) =>
    post("error", { message: String(reason) })
  );

  // The notation panel is far wider on iPad than on iPhone. Engraving at a
  // fixed scale leaves the score marooned in the corner of a large panel, so
  // the scale follows the available width.
  const scaleForWidth = (width) => {
    if (width >= 1000) return 1.8;
    if (width >= 800) return 1.55;
    if (width >= 640) return 1.3;
    return 1;
  };

  let appliedScale = 0;
  const applyScale = () => {
    const scale = scaleForWidth(window.innerWidth);
    if (scale === appliedScale) return;
    appliedScale = scale;
    try {
      api.settings.display.scale = scale;
      api.updateSettings();
      if (api.score) { api.render(); }
    } catch (error) {
      post("error", { message: "scale: " + String(error) });
    }
  };

  let resizeTimer = 0;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(applyScale, 180);
  });

  let lastTheme = null;

  window.stringMap = {
    setShowTab(enabled) {
      const profile = enabled ? alphaTab.StaveProfile.ScoreTab : alphaTab.StaveProfile.Score;
      if (api.settings.display.staveProfile === profile) return;
      api.settings.display.staveProfile = profile;
      api.updateSettings();
      if (api.score) api.render();
    },
    setTheme(theme) {
      if (!theme) return;
      lastTheme = theme;
      const parse = (hex) => {
        const n = parseInt(String(hex).replace("#", ""), 16);
        return new alphaTab.model.Color((n >> 16) & 255, (n >> 8) & 255, n & 255, 255);
      };
      const root = document.documentElement.style;
      root.setProperty("--paper", theme.paper);
      root.setProperty("--cursor-bar", theme.cursorBar);
      root.setProperty("--cursor-beat", theme.cursorBeat);
      root.setProperty("color-scheme", theme.dark ? "dark" : "light");
      try {
        const resources = api.settings.display.resources;
        resources.staffLineColor = parse(theme.staffLine);
        resources.barSeparatorColor = parse(theme.barSeparator);
        resources.barNumberColor = parse(theme.barNumber);
        resources.mainGlyphColor = parse(theme.mainGlyph);
        resources.secondaryGlyphColor = parse(theme.secondaryGlyph);
        resources.scoreInfoColor = parse(theme.scoreInfo);
        appliedScale = scaleForWidth(window.innerWidth);
        api.settings.display.scale = appliedScale;
        api.updateSettings();
        // Re-rendering without a score loaded throws; the next load() picks the
        // palette up anyway.
        if (api.score) { api.render(); }
      } catch (error) {
        post("error", { message: "theme: " + String(error) });
      }
    },
    load(alphaTex, identities = []) {
      sourceNotes = identities;
      applyScale();
      const host = document.getElementById("score");
      if (host) { host.style.visibility = "visible"; }
      api.tex(alphaTex);
    },
    // Hide rather than re-render: keeping the engraved score in the DOM while
    // the app reports the passage unplayable would invite misreading it.
    clear() {
      api.stop();
      const host = document.getElementById("score");
      if (host) { host.style.visibility = "hidden"; }
    },
    playPause() {
      return api.playPause();
    },
    pause() { api.pause(); },
    stop() {
      api.stop();
    },
    seek(milliseconds) {
      api.timePosition = Math.max(0, Number(milliseconds) || 0) / api.playbackSpeed;
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
