;(function() {
  'use strict';
  // Use the global shared helper functions and variables
  const __ext_callbackMap = window.__ext_callbackMap;
  const __ext_listeners = window.__ext_listeners;
  const __ext_randomString = window.__ext_randomString;
  const __ext_encodeForMessaging = window.__ext_encodeForMessaging;
  const __ext_decodeFromMessaging = window.__ext_decodeFromMessaging;
  const __ext_post = window.__ext_post;

  {{RUNTIME_BODY}}

  // Function for injecting lastError in callbacks
  window.__ext_injectLastError = function(error, callback, response) {
    const injectedError = { message: error.message || error }
    let seen = false
    const originalDesc =
      Object.getOwnPropertyDescriptor(chrome.runtime, "lastError")

    // override getter in-place
    Object.defineProperty(chrome.runtime, "lastError", {
      get() {
        seen = true;
        return injectedError;
      },
      configurable: true,
      enumerable: originalDesc.enumerable
    });

      try {
          // Handle both encoded responses (from real API calls) and raw values (from direct test calls)
          let decodedResponse;
          if (typeof response === 'string') {
              // This is a JSON-encoded response from the real API system
              const parsedResponse = JSON.parse(response);
              decodedResponse = __ext_decodeFromMessaging(parsedResponse);
          } else {
              // This is a raw value (e.g., from direct test calls)
              decodedResponse = response;
          }
          callback(decodedResponse);
      } catch (e) {
        // Error in callback execution
    } finally {
      Object.defineProperty(chrome.runtime, "lastError", originalDesc);

      // warn if nobody read it
      if (!seen) {
        console.warn('Unchecked runtime.lastError:', injectedError.message);
      }
    }
  }

  Object.defineProperty(window, '__EXT_invokeCallback__', {
    value(requestId, result, error) {
      const cb = __ext_callbackMap.get(requestId);
      if (cb) {
        try {
          if (error) {
            window.__ext_injectLastError(error, cb, result);
          } else {
            if (result === '') {
              cb()
            } else {
              // Result comes as a JSON string from Swift, parse it first
              const parsedResult = JSON.parse(result);
              const decoded = __ext_decodeFromMessaging(parsedResult);
              cb(decoded);
            }
          }
        }
        finally { __ext_callbackMap.delete(requestId) }
      }
    },
    writable: false,
    configurable: false,
    enumerable: false
  });
  // Inject into *both* background & content contexts
  Object.defineProperty(window, '__EXT_invokeListener__', {
    value(requestId, message, sender, isExternal, alreadyResponded) {
      let keepAlive = false;
      let responded = alreadyResponded;
      let listenersInvoked = 0;

      function sendResponse(response) {
        if (responded) return;
        responded = true;
        const encoded = __ext_encodeForMessaging(response);
        __ext_post.listenerResponseBrowserExtension.postMessage({ requestId, response: encoded });
      }

      for (const entry of __ext_listeners) {
        if (entry.external !== isExternal) continue;
        listenersInvoked++;
  
        try {
          const result = entry.callback(message, sender, sendResponse);
          if (result === true) {
            // listener wants to respond asynchronously
            keepAlive = true;
          }
        }
        catch (err) {
          console.error('onMessage listener threw:', err);
        }
      }
      return {"keepAlive": keepAlive, "responded": responded, "listenersInvoked": listenersInvoked};
    },
    writable: false,
    configurable: false,
    enumerable: false
  });
  // Add runtime to the existing chrome object
  Object.defineProperty(window.chrome, 'runtime', {
    value: runtime,
    writable: false,
    configurable: false,
    enumerable: true
  });
  true;
})();
