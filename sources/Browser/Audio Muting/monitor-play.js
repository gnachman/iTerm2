(function() {
    'use strict';
    const sessionSecret = "{{SECRET}}";
    
    // Cache to store audio detection results per element
    const audioDetectionCache = new WeakMap();
    
    // Audio detection function for WKWebView
    async function detectAudio(mediaElement) {
        // Check cache first
        if (audioDetectionCache.has(mediaElement)) {
            return audioDetectionCache.get(mediaElement);
        }
        
        let hasAudio = false;
        let reason = 'unknown';
        
        // Method 1: Check audioTracks (this often doesn't work properly in many cases)
        if (mediaElement.audioTracks && typeof mediaElement.audioTracks.length === 'number') {
            if (mediaElement.audioTracks.length > 0) {
                hasAudio = true;
                reason = `audioTracks reports ${mediaElement.audioTracks.length} track(s)`;
            } else {
                // audioTracks.length is 0, but this might be unreliable
                reason = 'audioTracks.length is 0 (may be unreliable)';
            }
        }
        
        // Method 2: Try captureStream API to detect audio tracks
        if (!hasAudio && mediaElement.captureStream) {
            try {
                const stream = mediaElement.captureStream();
                const audioTracks = stream.getAudioTracks();
                
                if (audioTracks.length > 0) {
                    hasAudio = true;
                    reason = `captureStream detected ${audioTracks.length} audio track(s)`;
                } else if (mediaElement.audioTracks?.length === 0) {
                    // If both methods agree there's no audio, we can be confident
                    hasAudio = false;
                    reason = 'both audioTracks and captureStream report no audio';
                }
                
                // Clean up
                audioTracks.forEach(track => track.stop());
            } catch (err) {
                console.debug('[iTerm2 Audio] captureStream detection failed:', err.message);
            }
        }
        
        // Method 3: Fallback - if we couldn't detect definitively and the element is ready,
        // assume it might have audio (better to have false positives than miss real audio)
        if (!hasAudio && reason === 'unknown' && mediaElement.readyState >= 2) {
            hasAudio = true;
            reason = 'assuming audio present (detection methods inconclusive)';
        }
        
        const result = { hasAudio, reason };
        
        // Cache the result
        audioDetectionCache.set(mediaElement, result);
        
        return result;
    }
    
    document.addEventListener('play', async function(e) {
        const target = e.target;
        
        // Detect if element has audio
        const audioInfo = await detectAudio(target);
        let { hasAudio, reason } = audioInfo;

        // Override: If muted or volume is 0, it won't make sound anyway
        if (target.muted || target.volume === 0) {
            hasAudio = false;
            reason = target.muted ? 'element is muted' : 'volume is 0';
        }

        // Log detailed info for diagnostics
        console.debug('[iTerm2 Audio] Play event:', {
            url: window.location.href,
            src: target?.src || target?.currentSrc || 'no src',
            hasAudio: hasAudio,
            reason: reason,
            audioTracks: target.audioTracks?.length,
            captureStreamSupported: !!target.captureStream,
            muted: target.muted,
            volume: target.volume,
            readyState: target.readyState
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
