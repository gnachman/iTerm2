// cloak-page-world.js
// Runs first in the .page world. In frames belonging to known
// browser-fingerprinting / captcha endpoints (Cloudflare Turnstile,
// hCaptcha, etc.) it hides our message-handler surface and sets
// window.__iTermBrowserCloak so the other page-world bridges (console
// wrap, Notification polyfill, geolocation polyfill, audio mute /
// monitor) skip installation. The result is a frame whose JS surface
// is indistinguishable from a vanilla WKWebView running Safari.

(function() {
    'use strict';
    try {
        const href = String(window.location.href || '');
        const host = String(window.location.hostname || '').toLowerCase();

        // Hostname checks for providers that dedicate an entire host to
        // the challenge surface.
        const isChallengeHost =
            /(^|\.)challenges\.cloudflare\.com$/.test(host) ||
            /(^|\.)hcaptcha\.com$/.test(host) ||
            /(^|\.)arkoselabs\.com$/.test(host) ||
            /(^|\.)funcaptcha\.com$/.test(host);

        // Path checks for providers that serve the challenge as a
        // sub-path of a general-purpose host. Google reCAPTCHA v2/v3
        // is primarily served from www.google.com/recaptcha/ and
        // www.gstatic.com/recaptcha/; recaptcha.net is the regional
        // fallback. This single test catches all three.
        const isChallengePath =
            /\/recaptcha\//i.test(href) ||
            /\/cdn-cgi\/challenge-platform\//i.test(href) ||
            /__cf_chl_/.test(href);

        const isChallengeFrame = isChallengeHost || isChallengePath;

        if (!isChallengeFrame) {
            return;
        }

        try {
            Object.defineProperty(window, '__iTermBrowserCloak', {
                value: true,
                writable: false,
                configurable: false,
                enumerable: false
            });
        } catch (e) {}

        // Real Safari does not expose window.webkit. WKWebView does, and
        // anything we register on window.webkit.messageHandlers (e.g.
        // iTermNotification, iTermGeolocation, iTerm2AudioHandler,
        // iTerm2ConsoleLog) is enumerable from the page. Strip the whole
        // namespace inside the challenge frame so the probe sees a
        // surface that matches stock Safari.
        try {
            delete window.webkit;
        } catch (e) {}
        try {
            if ('webkit' in window) {
                Object.defineProperty(window, 'webkit', {
                    value: undefined,
                    writable: true,
                    configurable: true,
                    enumerable: false
                });
            }
        } catch (e) {}
    } catch (e) {}
})();
