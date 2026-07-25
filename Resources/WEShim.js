// Wallpaper Engine web API shim.
//
// Injected at document start so wallpaper scripts find the globals they expect
// before they run. The native side pushes user properties by calling
// window.wallpaperPropertyListener.applyUserProperties(...) via evaluateJavaScript.
(function () {
  "use strict";

  // Audio listener: WE calls this ~20x/sec with a 128-float array (64L + 64R).
  // v1 stub: register the callback and feed a silent frame on a timer so
  // audio-reactive wallpapers render an idle state instead of throwing.
  window.__weAudioCallbacks = window.__weAudioCallbacks || [];
  window.wallpaperRegisterAudioListener = function (callback) {
    if (typeof callback === "function") {
      window.__weAudioCallbacks.push(callback);
    }
  };

  var SILENT = new Array(128).fill(0);
  setInterval(function () {
    for (var i = 0; i < window.__weAudioCallbacks.length; i++) {
      try { window.__weAudioCallbacks[i](SILENT); } catch (e) {}
    }
  }, 50);

  // Media integration (now-playing) — no-op stubs.
  window.wallpaperMediaIntegration = window.wallpaperMediaIntegration || {};
  window.wallpaperRegisterMediaStatusListener = window.wallpaperRegisterMediaStatusListener || function () {};
  window.wallpaperRegisterMediaPropertiesListener = window.wallpaperRegisterMediaPropertiesListener || function () {};
  window.wallpaperRegisterMediaThumbnailListener = window.wallpaperRegisterMediaThumbnailListener || function () {};
  window.wallpaperRegisterMediaTimelineListener = window.wallpaperRegisterMediaTimelineListener || function () {};

  // File-picker property helper — no-op in v1.
  window.wallpaperRequestRandomFileForProperty = window.wallpaperRequestRandomFileForProperty || function () {};

  // Ensure the listener object exists so early native pushes don't fail; the
  // wallpaper typically overwrites this with its own implementation.
  if (!window.wallpaperPropertyListener) {
    window.wallpaperPropertyListener = {};
  }
})();
