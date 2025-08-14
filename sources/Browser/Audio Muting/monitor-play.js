(function() {
    'use strict';
    const sessionSecret = "{{SECRET}}";
    document.addEventListener('play', function(e) {
        const target = e.target;

        // Check if this media element actually has audio
        let hasAudio = true;
        let reason = 'default assumption';

        // Check audioTracks if available
        if (target.audioTracks) {
            if (target.audioTracks.length === 0) {
                hasAudio = false;
                reason = 'audioTracks.length is 0';
            } else {
                hasAudio = true;
                reason = `has ${target.audioTracks.length} audio track(s)`;
            }
        }

        // If muted or volume is 0, it won't make sound anyway
        if (target.muted || target.volume === 0) {
            hasAudio = false;
            reason = target.muted ? 'video is muted' : 'volume is 0';
        }

        // Log key info for diagnostics
        console.debug('[iTerm2 Audio] Play event:', {
            url: window.location.href,
            src: target?.src || target?.currentSrc || 'no src',
            hasAudio: hasAudio,
            reason: reason,
            audioTracks: target.audioTracks?.length,
            muted: target.muted,
            volume: target.volume
        });

        // Only trigger if the media actually has audio and can make sound
        if (hasAudio) {
            window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({ event: 'play', sessionSecret: sessionSecret });
        }
    }, true);

    document.addEventListener('pause', function(e) {
        console.debug('[iTerm2 Audio] Pause event on', window.location.href);
        window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({ event: 'pause', sessionSecret: sessionSecret });
    }, true);
})();
