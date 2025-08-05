(function() {
    'use strict';
    const sessionSecret = "{{SECRET}}";
    document.addEventListener('play', function(e) {
        window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({ event: 'play', sessionSecret: sessionSecret });
    }, true);

    document.addEventListener('pause', function(e) {
        window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({ event: 'pause', sessionSecret: sessionSecret });
    }, true);
})();
