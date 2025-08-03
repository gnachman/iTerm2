;(function() {
    'use strict';

    const TAG = 'iTerm2Triggers';
    const sessionSecret = "{{SECRET}}";
    // This is a dictionary from string to Trigger Dictionary, which has keys defined in
    // Trigger.m (e.g., kTriggerRegexKey)
    let triggers = {{INITIAL_TRIGGERS}};
    // Map from trigger identifier to compiled regex
    let compiledRegexes = {};
    // Map from trigger identifier to compiled content regex (lazy-loaded)
    let compiledContentRegexes = {};

    console.debug(TAG, 'Initializing...');
    console.debug(TAG, 'window.webkit:', window.webkit);
    console.debug(TAG, 'window.webkit?.messageHandlers:', window.webkit?.messageHandlers);
    console.debug(TAG, 'Available message handlers:', window.webkit?.messageHandlers ? Object.keys(window.webkit.messageHandlers) : 'none');

    const _messageHandler = window.webkit?.messageHandlers?.iTerm2Trigger;
    const _postMessage = _messageHandler?.postMessage?.bind(_messageHandler);

    console.debug(TAG, '_messageHandler:', _messageHandler);
    console.debug(TAG, '_postMessage:', _postMessage);

    // Eagerly compile URL regexes for both URL triggers (matchType 1) and page content triggers (matchType 2)
    function compileTriggersRegexes(triggerDict) {
        console.debug(TAG, 'Compiling URL regexes:', triggerDict);
        const newCompiledRegexes = {};

        for (const [identifier, trigger] of Object.entries(triggerDict)) {
            const matchType = trigger.matchType || 0;
            console.debug(TAG, 'Trigger', identifier, 'matchType:', matchType);

            // Eagerly compile URL regex for both URL triggers (matchType 1) and page content triggers (matchType 2)
            if (matchType === 1 || matchType === 2) {
                const regex = trigger.regex;
                if (!regex) {
                    console.debug(TAG, 'Trigger', identifier, 'has no regex');
                    continue;
                }

                try {
                    newCompiledRegexes[identifier] = new RegExp(regex);
                    console.debug(TAG, 'Compiled URL regex for', identifier, ':', regex);
                } catch (error) {
                    console.error(TAG, 'Invalid URL regex pattern for', identifier, ':', regex, error.toString());
                }
            }
        }

        console.debug(TAG, 'Compiled URL regexes:', Object.keys(newCompiledRegexes));
        return newCompiledRegexes;
    }

    // Lazy compilation of content regex for page content triggers
    function getCompiledContentRegex(identifier, trigger) {
        if (compiledContentRegexes[identifier]) {
            return compiledContentRegexes[identifier];
        }

        const contentRegex = trigger.contentregex;
        if (!contentRegex) {
            console.debug(TAG, 'Trigger', identifier, 'has no content regex');
            return null;
        }

        try {
            const compiled = new RegExp(contentRegex);
            compiledContentRegexes[identifier] = compiled;
            console.debug(TAG, 'Lazily compiled content regex for', identifier, ':', contentRegex);
            return compiled;
        } catch (error) {
            console.error(TAG, 'Invalid content regex pattern for', identifier, ':', contentRegex, error.toString());
            // Cache the error so we don't try again
            compiledContentRegexes[identifier] = null;
            return null;
        }
    }

    function setTriggers(command) {
        console.debug(TAG, 'setTriggers called with:', command);
        const validated = validateCommand(command);
        if (!validated) {
            console.error(TAG, 'Invalid command');
            return;
        }
        triggers = command.triggers;
        compiledRegexes = compileTriggersRegexes(triggers);
        // Clear cached content regexes since triggers have changed
        compiledContentRegexes = {};

        // Check current URL against new triggers
        checkTriggers();
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
        console.debug(TAG, 'checkTriggers called, current URL:', window.location.href);

        if (!_postMessage) {
            console.error(TAG, 'Message handler unavailable');
            return;
        }

        const currentURL = window.location.href;
        const matches = [];

        console.debug(TAG, 'Checking', Object.keys(compiledRegexes).length, 'compiled regexes');

        // Check each compiled regex
        for (const [identifier, regex] of Object.entries(compiledRegexes)) {
            const trigger = triggers[identifier];
            if (!trigger) {
                console.debug(TAG, 'No trigger found for identifier:', identifier);
                continue;
            }

            const matchType = trigger.matchType || 0;
            const urlMatch = currentURL.match(regex);
            
            console.debug(TAG, 'Testing URL regex for', identifier, ':', regex, 'match:', urlMatch);

            if (urlMatch) {
                if (matchType === 1) {
                    // URL regex trigger - URL match is sufficient
                    matches.push({
                        matchType: 'urlRegex',
                        captures: Array.from(urlMatch),
                        identifier: identifier
                    });
                } else if (matchType === 2) {
                    // Page content trigger - URL matched, now check content
                    const contentRegex = getCompiledContentRegex(identifier, trigger);
                    if (contentRegex) {
                        const pageText = getPageTextContent();
                        const contentMatch = pageText.match(contentRegex);
                        
                        console.debug(TAG, 'Testing content regex for', identifier, ':', contentRegex, 'content match:', contentMatch);

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

        console.debug(TAG, 'Found', matches.length, 'matches');

        // If we found matches, post them
        if (matches.length > 0) {
            const matchEvent = {
                matches: matches
            };

            console.debug(TAG, 'Posting match event:', matchEvent);

            try {
                _postMessage({
                    sessionSecret: sessionSecret,
                    matchEvent: JSON.stringify(matchEvent)
                });
                console.debug(TAG, 'Successfully posted match event');
            } catch (error) {
                console.error(TAG, 'Failed to post message:', error.toString());
            }
        }
    }

    // Listen for document ready and URL changes
    function setupTriggerListeners() {
        console.debug(TAG, 'Setting up trigger listeners');

        // Check triggers when document loads (for every page load)
        document.addEventListener('DOMContentLoaded', () => {
            console.debug(TAG, 'DOMContentLoaded event fired');
            checkTriggers();
        });

        // Listen for popstate events (back/forward navigation)
        window.addEventListener('popstate', () => {
            console.debug(TAG, 'popstate event fired');
            checkTriggers();
        });

        // Listen for pushstate/replacestate (modern SPA navigation)
        const originalPushState = history.pushState;
        const originalReplaceState = history.replaceState;

        history.pushState = function(...args) {
            originalPushState.apply(this, args);
            console.debug(TAG, 'pushState called');
            setTimeout(checkTriggers, 0); // Async to let URL update
        };

        history.replaceState = function(...args) {
            originalReplaceState.apply(this, args);
            console.debug(TAG, 'replaceState called');
            setTimeout(checkTriggers, 0); // Async to let URL update
        };
    }

    // Initialize with the initial triggers
    compiledRegexes = compileTriggersRegexes(triggers);

    // Initialize trigger checking
    setupTriggerListeners();

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

