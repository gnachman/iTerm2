 (function() {
     'use strict';
     const TAG = '[ConsoleLogBridge]';

     // Safely grab the native handler (or stub)
     let _postMessage = () => {};
     if (window.webkit?.messageHandlers?.iTerm2ConsoleLog) {
         _postMessage = window.webkit.messageHandlers.iTerm2ConsoleLog
             .postMessage
             .bind(window.webkit.messageHandlers.iTerm2ConsoleLog);
     }

     // Circular-safe JSON serializer
     function serializeArg(arg) {
         if (arg instanceof Error) {
             return arg.stack || `${arg.name}: ${arg.message}`;
         }
         if (typeof arg === 'object' && arg !== null) {
             const seen = new WeakSet();
             return JSON.stringify(arg, (key, value) => {
                 if (typeof value === 'object' && value !== null) {
                     if (seen.has(value)) {
                         return '[Circular]';
                     }
                     seen.add(value);
                 }
                 if (typeof value === 'function') {
                     return value.toString();
                 }
                 return value;
             });
         }
         return String(arg);
     }

     // Wrap console.log / console.error
     const _oldLog = console.log;
     const _oldError = console.error;

     console.log = function(...args) {
         _oldLog.apply(console, args);
         try {
             const msg = args.map(serializeArg).join(' ');
             _postMessage(msg);
         }
         catch (e) {
             _oldError(TAG, 'failed to post log:', e);
         }
     };

     console.error = function(...args) {
         _oldError.apply(console, args);
         try {
             const msg = args.map(serializeArg).join(' ');
             _postMessage(msg);
         }
         catch (e) {
             _oldError(TAG, 'failed to post error:', e);
         }
     };

     {{LOG_ERRORS}}
 })();
