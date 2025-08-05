(function() {
    'use strict';
    const secret = "{{SECRET}}";

    // Grab the originals
    const RealAC = window.AudioContext;
    const RealOAC = window.OfflineAudioContext;
    const RealWAC = window.webkitAudioContext;

    // Build wrappers that still call the real constructors
    function WrappedAC(...args) {
        window.webkit.messageHandlers.audioHandler.postMessage({
            event: 'audioContextCreated', sessionSecret: secret
        });
        return new RealAC(...args);
    }
    WrappedAC.prototype = RealAC.prototype;

    function WrappedOAC(...args) {
        window.webkit.messageHandlers.audioHandler.postMessage({
            event: 'offlineAudioContextCreated', sessionSecret: secret
        });
        return new RealOAC(...args);
    }
    WrappedOAC.prototype = RealOAC.prototype;

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

    // 5. Freeze the prototypes so methods can’t be altered
    Object.freeze(RealAC.prototype);
    Object.freeze(RealOAC.prototype);

    // 6. (Optional) Prevent any future additions to these constructors
    Object.freeze(WrappedAC);
    Object.freeze(WrappedOAC);
})();

