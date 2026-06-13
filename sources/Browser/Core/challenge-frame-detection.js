// challenge-frame-detection.js
// A self-contained expression that evaluates to true when the current
// frame belongs to a known browser-fingerprinting / captcha endpoint
// (Cloudflare Turnstile, hCaptcha, Arkose/FunCaptcha, reCAPTCHA). It is
// meant to be embedded with the template loader's INCLUDE directive
// inside an `if (...)` so the cloak and the page-world bridges can each
// independently decide to bail out. This is deliberately stateless: it
// reads nothing from and writes nothing to the window object, so it
// leaves no marker a challenge probe could detect. Real Safari exposes
// no such property, which would otherwise be a stronger fingerprint
// than the surface the cloak is trying to hide.
(function() {
    'use strict';
    try {
        const host = String(window.location.hostname || '').toLowerCase();
        // Match against the pathname (not the full href) so a page cannot
        // trip detection by stuffing a marker string into its query or
        // fragment. Path prefixes are anchored at the start of the path.
        const path = String(window.location.pathname || '');
        const search = String(window.location.search || '');

        // Hostname checks for providers that dedicate an entire host to
        // the challenge surface.
        const isChallengeHost =
            /(^|\.)challenges\.cloudflare\.com$/.test(host) ||
            /(^|\.)hcaptcha\.com$/.test(host) ||
            /(^|\.)arkoselabs\.com$/.test(host) ||
            /(^|\.)funcaptcha\.com$/.test(host);

        // Path checks for providers that serve the challenge as a
        // sub-path of a general-purpose host. Google reCAPTCHA v2/v3 is
        // primarily served from www.google.com/recaptcha/ and
        // www.gstatic.com/recaptcha/; recaptcha.net is the regional
        // fallback. This single anchored test catches all three.
        // Cloudflare's managed challenge lives under
        // /cdn-cgi/challenge-platform/, and its interstitial sets a
        // __cf_chl_ query parameter; require that to be an actual query
        // key rather than an arbitrary substring of the URL.
        const isChallengePath =
            /^\/recaptcha\//i.test(path) ||
            /^\/cdn-cgi\/challenge-platform\//i.test(path) ||
            /(^|[?&])__cf_chl_/.test(search);

        return isChallengeHost || isChallengePath;
    } catch (e) {
        return false;
    }
})()
