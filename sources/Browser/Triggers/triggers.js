;(function() {
    'use strict';

    const TAG = 'iTerm2Triggers';
    const sessionSecret = "{{SECRET}}";
    // This is a dictionary from string to Trigger Dictionary, which has keys defined in
    // Trigger.m (e.g., kTriggerRegexKey)
    let triggers = {};
    // Map from trigger identifier to compiled regex
    let compiledRegexes = {};
    // Map from trigger identifier to compiled content regex (lazy-loaded)
    let compiledContentRegexes = {};

    console.log(TAG, 'Initializing...');
    console.log(TAG, 'window.webkit:', window.webkit);
    console.log(TAG, 'window.webkit?.messageHandlers:', window.webkit?.messageHandlers);
    console.log(TAG, 'Available message handlers:', window.webkit?.messageHandlers ? Object.keys(window.webkit.messageHandlers) : 'none');

    const _messageHandler = window.webkit?.messageHandlers?.iTerm2Trigger;
    const _postMessage = _messageHandler?.postMessage?.bind(_messageHandler);

    console.log(TAG, '_messageHandler:', _messageHandler);
    console.log(TAG, '_postMessage:', _postMessage);

    // Request triggers from the host on startup
    function requestTriggers() {
        if (!_postMessage) {
            console.error(TAG, 'Message handler unavailable for requesting triggers');
            return;
        }

        console.log(TAG, 'Requesting triggers from host');
        try {
            _postMessage({
                sessionSecret: sessionSecret,
                requestTriggers: true
            });
            console.log(TAG, 'Successfully sent trigger request');
        } catch (error) {
            console.error(TAG, 'Failed to request triggers:', error.toString());
        }
    }

    // Eagerly compile URL regexes for both URL triggers (matchType 1) and page content triggers (matchType 2)
    function compileTriggersRegexes(triggerDict) {
        console.log(TAG, 'Compiling URL regexes:', triggerDict);
        const newCompiledRegexes = {};

        for (const [identifier, trigger] of Object.entries(triggerDict)) {
            const matchType = trigger.matchType || 0;
            console.log(TAG, 'Trigger', identifier, 'matchType:', matchType);

            // Eagerly compile URL regex for both URL triggers (matchType 1) and page content triggers (matchType 2)
            if (matchType === 1 || matchType === 2) {
                const regex = trigger.regex;
                if (!regex) {
                    console.log(TAG, 'Trigger', identifier, 'has no regex');
                    continue;
                }

                try {
                    newCompiledRegexes[identifier] = new RegExp(regex);
                    console.log(TAG, 'Compiled URL regex for', identifier, ':', regex);
                } catch (error) {
                    console.error(TAG, 'Invalid URL regex pattern for', identifier, ':', regex, error.toString());
                }
            }
        }

        console.log(TAG, 'Compiled URL regexes:', Object.keys(newCompiledRegexes));
        return newCompiledRegexes;
    }

    // Lazy compilation of content regex for page content triggers
    function getCompiledContentRegex(identifier, trigger) {
        if (compiledContentRegexes[identifier]) {
            return compiledContentRegexes[identifier];
        }

        const contentRegex = trigger.contentregex;
        if (!contentRegex) {
            console.log(TAG, 'Trigger', identifier, 'has no content regex');
            return null;
        }

        try {
            const compiled = new RegExp(contentRegex);
            compiledContentRegexes[identifier] = compiled;
            console.log(TAG, 'Lazily compiled content regex for', identifier, ':', contentRegex);
            return compiled;
        } catch (error) {
            console.error(TAG, 'Invalid content regex pattern for', identifier, ':', contentRegex, error.toString());
            // Cache the error so we don't try again
            compiledContentRegexes[identifier] = null;
            return null;
        }
    }

    function setTriggers(command) {
        try {
            console.log(TAG, 'setTriggers called with:', command);
            const validated = validateCommand(command);
            if (!validated) {
                console.error(TAG, 'Invalid command');
                return;
            }
            triggers = command.triggers;
            console.log(TAG, 'triggers is now set to:', triggers);
            compiledRegexes = compileTriggersRegexes(triggers);
            // Clear cached content regexes since triggers have changed
            compiledContentRegexes = {};

            // Check current URL against new triggers
            checkTriggers();
        } catch(e) {
            console.error(e.toString());
            console.error(e);
            throw e;
        }
    }

    function validateSessionSecret(secret) {
        return secret === sessionSecret;
    }

    function validateCommand(command) {
        if (!command || typeof command !== 'object') {
            return null;
        }

        // Validate session secret
        if (!validateSessionSecret(command.sessionSecret)) {
            console.error(TAG, 'Invalid session secret');
            return null;
        }
        return command
    }

    // Get page text content for content matching
    function getPageTextContent() {
        // Get visible text content from the document
        return document.body ? document.body.innerText || document.body.textContent || '' : '';
    }

    // Check URL and page content against triggers and post matches
    function checkTriggers() {
        console.log(TAG, 'checkTriggers called, current URL:', window.location.href);

        if (!_postMessage) {
            console.error(TAG, 'Message handler unavailable');
            return;
        }

        const currentURL = window.location.href;
        const matches = [];

        console.log(TAG, 'Checking', Object.keys(compiledRegexes).length, 'compiled regexes');

        // Check each compiled regex
        for (const [identifier, regex] of Object.entries(compiledRegexes)) {
            const trigger = triggers[identifier];
            if (!trigger) {
                console.log(TAG, 'No trigger found for identifier:', identifier);
                continue;
            }

            const matchType = trigger.matchType || 0;
            const urlMatch = currentURL.match(regex);
            
            console.log(TAG, 'Testing URL regex for', identifier, ':', regex, 'match:', urlMatch);

            if (urlMatch) {
                if (matchType === 1) {
                    // URL regex trigger - URL match is sufficient
                    matches.push({
                        matchType: 'urlRegex',
                        urlCaptures: Array.from(urlMatch),
                        identifier: identifier
                    });
                } else if (matchType === 2) {
                    // Page content trigger - URL matched, now check content
                    const contentRegex = getCompiledContentRegex(identifier, trigger);
                    if (contentRegex) {
                        const pageText = getPageTextContent();
                        const contentMatch = pageText.match(contentRegex);
                        
                        console.log(TAG, 'Testing content regex for', identifier, ':', contentRegex, 'content match:', contentMatch);

                        if (contentMatch) {
                            matches.push({
                                matchType: 'pageContent',
                                urlCaptures: Array.from(urlMatch),
                                contentCaptures: Array.from(contentMatch),
                                identifier: identifier
                            });
                        }
                    }
                }
            }
        }

        console.log(TAG, 'Found', matches.length, 'matches');

        // If we found matches, post them
        if (matches.length > 0) {
            const matchEvent = {
                matches: matches
            };

            console.log(TAG, 'Posting match event:', matchEvent);

            try {
                _postMessage({
                    sessionSecret: sessionSecret,
                    matchEvent: JSON.stringify(matchEvent)
                });
                console.log(TAG, 'Successfully posted match event');
            } catch (error) {
                console.error(TAG, 'Failed to post message:', error.toString());
            }
        }
    }

    // Listen for document ready and URL changes
    function setupTriggerListeners() {
        console.log(TAG, 'Setting up trigger listeners');

        // Check triggers when document loads (for every page load)
        document.addEventListener('DOMContentLoaded', () => {
            console.log(TAG, 'DOMContentLoaded event fired');
            checkTriggers();
        });

        // Listen for popstate events (back/forward navigation)
        window.addEventListener('popstate', () => {
            console.log(TAG, 'popstate event fired');
            checkTriggers();
        });

        // Listen for pushstate/replacestate (modern SPA navigation)
        const originalPushState = history.pushState;
        const originalReplaceState = history.replaceState;

        history.pushState = function(...args) {
            originalPushState.apply(this, args);
            console.log(TAG, 'pushState called');
            setTimeout(checkTriggers, 0); // Async to let URL update
        };

        history.replaceState = function(...args) {
            originalReplaceState.apply(this, args);
            console.log(TAG, 'replaceState called');
            setTimeout(checkTriggers, 0); // Async to let URL update
        };
    }

    // Initialize trigger checking
    setupTriggerListeners();

    // Request triggers from the host
    requestTriggers();

    const api = {
        setTriggers
    };

    Object.freeze(api);
    Object.freeze(api.setTriggers);

    Object.defineProperty(window, TAG, {
        value: api,
        writable: false,
        configurable: false,
        enumerable: true
    });
    true;
})();

