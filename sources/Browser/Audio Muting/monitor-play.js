(function() {
    'use strict';
    const sessionSecret = "{{SECRET}}";

    // Cache to store audio detection results per element
    const audioDetectionCache = new WeakMap();
    console.debug('[iTerm2 Audio] monitor-play.js loaded');

    // Wrap play() method on HTMLMediaElement prototype
    const originalPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function(...args) {
        console.debug('[iTerm2 Audio] play() method called directly on', this.tagName, 'element');
        console.debug('[iTerm2 Audio] Element state:', {
            src: this.src,
            currentSrc: this.currentSrc,
            muted: this.muted,
            volume: this.volume,
            readyState: this.readyState,
            paused: this.paused,
            autoplay: this.autoplay
        });

        // Trigger our detection immediately
        detectAudio(this).then(audioInfo => {
            console.debug('[iTerm2 Audio] detectAudio resolved with:', audioInfo);
            let { hasAudio, reason } = audioInfo;

            // Override: If muted or volume is 0, it won't make sound anyway
            if (this.muted || this.volume === 0) {
                hasAudio = false;
                reason = this.muted ? 'element is muted' : 'volume is 0';
                console.debug('[iTerm2 Audio] Overriding detection due to mute/volume');
            }

            if (hasAudio) {
                console.debug('[iTerm2 Audio] play() method will produce audio:', reason);
                console.debug('[iTerm2 Audio] Sending message to handler...');
                try {
                    window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({
                        event: 'play',
                        sessionSecret: sessionSecret
                    });
                    console.debug('[iTerm2 Audio] Message sent successfully');
                } catch (err) {
                    console.error('[iTerm2 Audio] Failed to send message:', err);
                }
            } else {
                console.debug('[iTerm2 Audio] Not sending message, hasAudio=false, reason:', reason);
            }
        }).catch(err => {
            console.debug('[iTerm2 Audio] detectAudio error:', err);
        });

        // Call the original play method
        return originalPlay.apply(this, args);
    };

    // Audio detection function for WKWebView
    async function detectAudio(mediaElement) {
        console.debug(`[iTerm2 Audio] detectAudio on ${mediaElement}`);
        // Check cache first
        if (audioDetectionCache.has(mediaElement)) {
            console.debug('[iTerm2 Audio] Using cached result');
            return audioDetectionCache.get(mediaElement);
        }

        let hasAudio = false;
        let reason = 'unknown';

        console.debug('[iTerm2 Audio] Checking audioTracks...');
        // Method 1: Check audioTracks (this often doesn't work properly in many cases)
        if (mediaElement.audioTracks && typeof mediaElement.audioTracks.length === 'number') {
            console.debug(`[iTerm2 Audio] audioTracks.length = ${mediaElement.audioTracks.length}`);
            if (mediaElement.audioTracks.length > 0) {
                hasAudio = true;
                reason = `audioTracks reports ${mediaElement.audioTracks.length} track(s)`;
            } else if (mediaElement.readyState >= 2) {
                // Only trust audioTracks.length = 0 if metadata is loaded
                // readyState 2 = HAVE_CURRENT_DATA, 3 = HAVE_FUTURE_DATA, 4 = HAVE_ENOUGH_DATA
                hasAudio = false;
                reason = 'audioTracks.length is 0 (metadata loaded)';
            } else {
                // audioTracks.length is 0 but metadata not loaded yet - can't trust this
                console.debug(`[iTerm2 Audio] audioTracks is 0 but readyState=${mediaElement.readyState} (metadata not loaded)`);
                // Keep reason as 'unknown' so the fallback will trigger
                reason = 'unknown';
            }
        } else {
            console.debug('[iTerm2 Audio] audioTracks not available or not a number');
        }

        console.debug('[iTerm2 Audio] Checking captureStream...');
        // Method 2: Try captureStream API to detect audio tracks
        if (!hasAudio && mediaElement.captureStream) {
            try {
                const stream = mediaElement.captureStream();
                const audioTracks = stream.getAudioTracks();
                console.debug(`[iTerm2 Audio] captureStream audioTracks.length = ${audioTracks.length}`);

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
        } else if (!mediaElement.captureStream) {
            console.debug('[iTerm2 Audio] captureStream not available');
        }

        console.debug('[iTerm2 Audio] Checking mozHasAudio...');
        // Method 3: Check mozHasAudio for Firefox
        if (!hasAudio && typeof mediaElement.mozHasAudio === 'boolean') {
            console.debug(`[iTerm2 Audio] mozHasAudio = ${mediaElement.mozHasAudio}`);
            hasAudio = mediaElement.mozHasAudio;
            reason = hasAudio ? 'mozHasAudio is true' : 'mozHasAudio is false';
        } else {
            console.debug('[iTerm2 Audio] mozHasAudio not available');
        }

        // Method 4: Fallback - if we couldn't detect definitively,
        // assume it might have audio (better to have false positives than miss real audio)
        // This includes when metadata hasn't loaded yet
        if (!hasAudio && reason === 'unknown') {
            console.debug('[iTerm2 Audio] Using fallback - assuming audio present');
            hasAudio = true;
            reason = 'assuming audio present (metadata not loaded or detection inconclusive)';
        }

        const result = { hasAudio, reason };
        console.debug('[iTerm2 Audio] Final detection result:', result);

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

    // Monitor for HTML Audio/Video element creation
    const originalAudio = window.Audio;
    const originalCreateElement = document.createElement;

    // Wrap Audio constructor
    function WrappedAudio(...args) {
        console.debug('[iTerm2 Audio] Audio element created via constructor');
        const audio = new originalAudio(...args);

        // Check if autoplay is set
        if (audio.autoplay) {
            console.debug('[iTerm2 Audio] Audio element has autoplay');
            window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({
                event: 'play',
                sessionSecret: sessionSecret
            });
        }

        // Monitor autoplay property changes
        let autoplayValue = audio.autoplay;
        Object.defineProperty(audio, 'autoplay', {
            get() { return autoplayValue; },
            set(value) {
                autoplayValue = value;
                if (value) {
                    console.debug('[iTerm2 Audio] Audio element autoplay enabled');
                    window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({
                        event: 'play',
                        sessionSecret: sessionSecret
                    });
                }
            },
            configurable: true
        });

        return audio;
    }
    // Preserve the prototype chain
    WrappedAudio.prototype = originalAudio.prototype;
    window.Audio = WrappedAudio;

    // Wrap createElement for audio/video tags
    document.createElement = function(tagName, ...args) {
        const element = originalCreateElement.call(this, tagName, ...args);

        if (tagName.toLowerCase() === 'audio' || tagName.toLowerCase() === 'video') {
            console.debug(`[iTerm2 Audio] ${tagName} element created via createElement`);

            // Monitor autoplay attribute
            const originalSetAttribute = element.setAttribute;
            element.setAttribute = function(name, value) {
                if (name === 'autoplay') {
                    console.debug(`[iTerm2 Audio] ${tagName} autoplay attribute set`);
                    window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({
                        event: 'play',
                        sessionSecret: sessionSecret
                    });
                }
                return originalSetAttribute.call(this, name, value);
            };

            // Monitor autoplay property
            let autoplayValue = element.autoplay;
            Object.defineProperty(element, 'autoplay', {
                get() { return autoplayValue; },
                set(value) {
                    autoplayValue = value;
                    if (value) {
                        console.debug(`[iTerm2 Audio] ${tagName} autoplay property set to true`);
                        window.webkit.messageHandlers.iTerm2AudioHandler.postMessage({
                            event: 'play',
                            sessionSecret: sessionSecret
                        });
                    }
                },
                configurable: true
            });
        }

        return element;
    };
})();
