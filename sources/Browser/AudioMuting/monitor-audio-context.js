(function() {
    'use strict';
    const secret = "{{SECRET}}";

    console.debug('[iTerm2 Audio] monitor-audio-context.js loaded');

    // Grab the originals
    const RealAC = window.AudioContext;
    const RealOAC = window.OfflineAudioContext;
    const RealWAC = window.webkitAudioContext;

    // Build proper wrapper classes that extend the real constructors
    class WrappedAC extends RealAC {
        constructor(...args) {
            console.debug('[iTerm2 Audio] AudioContext created on', window.location.href);
            super(...args);
            window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({
                event: 'audioContextCreated', sessionSecret: secret
            });
        }
    }

    class WrappedOAC extends RealOAC {
        constructor(...args) {
            console.debug('[iTerm2 Audio] OfflineAudioContext created on', window.location.href);
            super(...args);
            window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({
                event: 'offlineAudioContextCreated', sessionSecret: secret
            });
        }
    }

    // 3. Redefine on window as non-writable, non-configurable
    Object.defineProperty(window, 'AudioContext', {
        value: WrappedAC,
        writable: false,
        configurable: false,
        enumerable: true
    });
    Object.defineProperty(window, 'OfflineAudioContext', {
        value: WrappedOAC,
        writable: false,
        configurable: false,
        enumerable: true
    });

    // 4. Also lock down the WebKit alias if present
    if (RealWAC) {
        Object.defineProperty(window, 'webkitAudioContext', {
            value: WrappedAC,
            writable: false,
            configurable: false,
            enumerable: true
        });
    }

    // 5. Freeze the prototypes so methods can't be altered
    Object.freeze(RealAC.prototype);
    Object.freeze(RealOAC.prototype);

    // 6. (Optional) Prevent any future additions to these constructors
    Object.freeze(WrappedAC);
    Object.freeze(WrappedOAC);
})();

