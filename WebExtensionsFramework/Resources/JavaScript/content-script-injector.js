// WebExtensions Framework Injection Script for Extension: {{EXTENSION_ID}}
// This script handles content script injection for a single extension in its isolated content world

(function() {
    'use strict';

    const extensionScripts = {{SCRIPTS_JSON}};
    const extensionId = '{{EXTENSION_ID}}';

    // URL pattern matching functions
    function matchesPattern(url, pattern) {
        if (pattern === '<all_urls>') {
            return true;
        }

        // Convert extension pattern to regex
        // Basic implementation - would need full pattern matching for production
        const regexPattern = pattern
            .replace(/\*/g, '.*')
            .replace(/\./g, '\\.')
            .replace(/\?/g, '\\?');

        try {
            const regex = new RegExp('^' + regexPattern + '$');
            return regex.test(url);
        } catch (e) {
            console.warn('Extension', extensionId, 'invalid pattern:', pattern, e);
            return false;
        }
    }

    function matchesPatterns(url, patterns) {
        return patterns.some(pattern => matchesPattern(url, pattern));
    }

    function shouldExecuteScript(script, currentURL, currentTiming) {
        return matchesPatterns(currentURL, script.patterns) &&
               script.runAt === currentTiming;
    }

    function executeScriptsAtTiming(timing) {
        const currentURL = window.location.href;

        extensionScripts.forEach(script => {
            if (shouldExecuteScript(script, currentURL, timing)) {
                script.scripts.forEach((scriptCode, index) => {
                    try {
                        // Execute the script in a function to provide some isolation
                        const scriptFunction = new Function(scriptCode);
                        scriptFunction();
                    } catch (error) {
                        console.error('Extension', extensionId, 'error executing script', index, ':', error);
                    }
                });
            }
        });
    }

    // Execute document_start scripts immediately if document is still loading
    if (document.readyState === 'loading') {
        executeScriptsAtTiming('document_start');
    }

    // Set up listeners for document_end and document_idle
    function onDOMContentLoaded() {
        executeScriptsAtTiming('document_end');

        // document_idle typically fires after DOMContentLoaded when the page is "idle"
        // For simplicity, we'll execute it shortly after document_end
        setTimeout(() => {
            executeScriptsAtTiming('document_idle');
        }, 100);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', onDOMContentLoaded);
    } else {
        // Document already loaded, execute document_end/idle scripts immediately
        onDOMContentLoaded();
    }

})();
