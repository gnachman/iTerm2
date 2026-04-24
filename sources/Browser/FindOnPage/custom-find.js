(function() {
    'use strict';

    let verbose = 0;
    {{INCLUDE:graph-discovery-api.js}}
    {{INCLUDE:find-security.js}}
    {{INCLUDE:find-constants.js}}
    {{INCLUDE:find-utils.js}}
    {{INCLUDE:find-global-click.js}}
    {{INCLUDE:find-segment.js}}
    {{INCLUDE:find-text-segment.js}}
    {{INCLUDE:find-iframe-segment.js}}
    {{INCLUDE:find-match.js}}
    {{INCLUDE:find-engine.js}}
    {{INCLUDE:find-api.js}}
    {{INCLUDE:find-highlighter.js}}
    {{INCLUDE:find-nav.js}}

    injectStyles();

    // Install global handlers
    window.addEventListener('message', handleGlobalMessage);

    // Install global click handler
    document.addEventListener('click', handleGlobalClick, true);

})();
