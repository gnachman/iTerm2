// transparent-background.js
// Injects CSS to make webpage backgrounds transparent for see-through effect
(function() {
    'use strict';

    const style = document.createElement('style');
    style.id = 'iterm2-transparent-background';
    style.textContent = `
        html, body {
            background-color: transparent !important;
            background-image: none !important;
        }
    `;

    // Insert at document start to prevent flash of opaque background
    if (document.head) {
        document.head.insertBefore(style, document.head.firstChild);
    } else {
        // If head doesn't exist yet, wait for it
        const observer = new MutationObserver(function(mutations, obs) {
            if (document.head) {
                document.head.insertBefore(style, document.head.firstChild);
                obs.disconnect();
            }
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
    }
})();
