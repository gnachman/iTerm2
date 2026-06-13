// cloak-page-world.js
// Runs first in the .page world. In frames belonging to known
// browser-fingerprinting / captcha endpoints (Cloudflare Turnstile,
// hCaptcha, etc.) it strips window.webkit so the challenge probe sees a
// surface that matches stock Safari. The page-world bridges (console
// wrap, Notification polyfill, geolocation polyfill, audio mute /
// monitor) make the same challenge-frame decision independently using
// the shared challenge-frame-detection snippet, so we do not communicate
// through any window property: a marker on window would itself be a
// detectable fingerprint (real Safari has no such property), defeating
// the purpose of the cloak.

(function() {
    'use strict';
    try {
        if (!({{INCLUDE:challenge-frame-detection.js}})) {
            return;
        }

        // Real Safari does not expose window.webkit. WKWebView does, and
        // anything we register on window.webkit.messageHandlers (e.g.
        // iTermNotification, iTermGeolocation, iTerm2AudioHandler,
        // iTerm2ConsoleLog) is enumerable from the page. Strip the whole
        // namespace inside the challenge frame so the probe sees a
        // surface that matches stock Safari.
        // On current WKWebView window.webkit is a configurable property,
        // so the delete removes it cleanly and the namespace is gone. We
        // intentionally do not install a stand-in if the delete ever
        // fails: an own "webkit" property whose value is undefined is a
        // cleaner fingerprint than the original (real Safari has no such
        // property at all), so it would defeat the purpose of the cloak.
        try {
            delete window.webkit;
        } catch (e) {}
    } catch (e) {}
})();
