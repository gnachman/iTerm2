;(function() {
    'use strict';
    try {
        const secret = '{{SECRET}}';

        // internal state
        const gainNodes = [];
        const originalGainValues = new WeakMap();
        const originalVolumes = new WeakMap();
        let muted = false;

        // apply muted/unmuted state to an HTMLMediaElement
        function applyStateToElem(e) {
            try {
                if (muted) {
                    // Store original volume before muting
                    if (!originalVolumes.has(e) && typeof e.volume === 'number') {
                        originalVolumes.set(e, e.volume);
                    }
                    e.muted = true;
                    if (typeof e.volume === 'number' && !Object.isFrozen(e)) {
                        e.volume = 0;
                    }
                } else {
                    e.muted = false;
                    if (typeof e.volume === 'number' && !Object.isFrozen(e)) {
                        // Restore original volume or default to 1.0
                        const originalVolume = originalVolumes.get(e);
                        e.volume = originalVolume !== undefined ? originalVolume : 1.0;
                    }
                }
            } catch (err) {
                console.warn("[iTerm2-AudioMute] Failed to apply mute state to element:", err);
            }
        }

        // wrap an AudioContext constructor so we can zero out every GainNode
        function wrapContext(Native) {
            return function() {
                const ctx = new Native(...arguments);
                const origCreateGain = ctx.createGain;
                ctx.createGain = function() {
                    const gain = origCreateGain.call(this);
                    gainNodes.push(gain);
                    // Store original gain value
                    if (!originalGainValues.has(gain)) {
                        originalGainValues.set(gain, gain.gain.value);
                    }
                    if (muted) {
                        gain.gain.value = 0;
                    }
                    return gain;
                };
                return ctx;
            };
        }

        // Check if we can modify AudioContext before trying
        const audioContextDescriptor = Object.getOwnPropertyDescriptor(window, 'AudioContext');
        const canModifyAudioContext = !audioContextDescriptor || audioContextDescriptor.configurable || audioContextDescriptor.writable;
        
        if (window.AudioContext && canModifyAudioContext) {
            try {
                const OriginalAudioContext = window.AudioContext;
                window.AudioContext = wrapContext(OriginalAudioContext);
                window.AudioContext.prototype = OriginalAudioContext.prototype;
            } catch (err) {
                console.warn("[iTerm2-AudioMute] Failed to wrap AudioContext:", err);
            }
        } else if (window.AudioContext) {
            console.warn("[iTerm2-AudioMute] Cannot modify AudioContext - property is not writable/configurable");
        }
        
        const offlineAudioContextDescriptor = Object.getOwnPropertyDescriptor(window, 'OfflineAudioContext');
        const canModifyOfflineAudioContext = !offlineAudioContextDescriptor || offlineAudioContextDescriptor.configurable || offlineAudioContextDescriptor.writable;
        
        if (window.OfflineAudioContext && canModifyOfflineAudioContext) {
            try {
                const OriginalOfflineAudioContext = window.OfflineAudioContext;
                window.OfflineAudioContext = wrapContext(OriginalOfflineAudioContext);
                window.OfflineAudioContext.prototype = OriginalOfflineAudioContext.prototype;
            } catch (err) {
                console.warn("[iTerm2-AudioMute] Failed to wrap OfflineAudioContext:", err);
            }
        } else if (window.OfflineAudioContext) {
            console.warn("[iTerm2-AudioMute] Cannot modify OfflineAudioContext - property is not writable/configurable");
        }

        // API methods
        function mute(sessionSecret) {
            if (sessionSecret != secret) return;
            muted = true;
            const elements = document.querySelectorAll('audio,video');
            elements.forEach(applyStateToElem);
            gainNodes.forEach(g => {
                if (!originalGainValues.has(g)) {
                    originalGainValues.set(g, g.gain.value);
                }
                g.gain.value = 0;
            });
        }
        function unmute(sessionSecret) {
            if (sessionSecret != secret) return;
            muted = false;
            const elements = document.querySelectorAll('audio,video');
            elements.forEach(applyStateToElem);
            gainNodes.forEach(g => {
                const originalValue = originalGainValues.get(g);
                g.gain.value = originalValue !== undefined ? originalValue : 1;
            });
        }

        // expose only a frozen API on window
        const api = { mute, unmute };
        Object.freeze(api);
        Object.freeze(api.mute);
        Object.freeze(api.unmute);

        // verify freeze
        const TEST_FREEZE = Object.isFrozen(api)
        && Object.isFrozen(api.mute)
        && Object.isFrozen(api.unmute);

        // Check if property already exists
        if (window.hasOwnProperty('iTerm2AudioMuting')) {
            console.warn("[iTerm2-AudioMute] iTerm2AudioMuting already exists on window");
            return;
        }
        
        // Check if we can define the property
        const descriptor = Object.getOwnPropertyDescriptor(window, 'iTerm2AudioMuting');
        if (descriptor && !descriptor.configurable) {
            console.warn("[iTerm2-AudioMute] Cannot define iTerm2AudioMuting - property exists and is not configurable");
            return;
        }
        
        try {
            Object.defineProperty(window, "iTerm2AudioMuting", {
                value: api,
                writable: false,
                configurable: false,
                enumerable: true
            });
        } catch (defineError) {
            console.error("[iTerm2-AudioMute] Failed to define iTerm2AudioMuting:", defineError);
            // Fallback: try simple assignment
            try {
                window.iTerm2AudioMuting = api;
            } catch (assignError) {
                console.error("[iTerm2-AudioMute] Failed to assign iTerm2AudioMuting:", assignError);
            }
        }

        // catch existing and future media elements
        document.addEventListener("DOMContentLoaded", function() {
            document.querySelectorAll("audio,video").forEach(applyStateToElem);
        });
        new MutationObserver(function(records) {
            for (let rec of records) {
                for (let node of rec.addedNodes) {
                    if (node.tagName === "AUDIO" || node.tagName === "VIDEO") {
                        applyStateToElem(node);
                    } else if (node.querySelectorAll) {
                        node.querySelectorAll("audio,video").forEach(applyStateToElem);
                    }
                }
            }
        }).observe(document, { childList: true, subtree: true });
        
    } catch (e) {
        console.error("[iTerm2-AudioMute] Error while loading mute-audio:", e.toString());
        console.error("[iTerm2-AudioMute] Stack:", e.stack);
    }
})();
true;
