 (function() {
     'use strict';
     try {
        document.addEventListener("selectionchange", function(e) {
            const sel = window.getSelection().toString();
            // avoid spamming identical values
            if (sel === window.__lastSelection) return;
            window.__lastSelection = sel;
            window.webkit.messageHandlers.iTermSelectionMonitor.postMessage({ selection: sel, sessionSecret: "{{SECRET}}"});
        });
     } catch (err) {
         console.error(
             '[monitor-selection error]',
             'message:', err.message,
             'stack:', err.stack
         );
     }
     return true;
 })();
