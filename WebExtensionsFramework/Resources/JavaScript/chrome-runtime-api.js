;(function() {
  'use strict';
  const __ext_callbackMap = new Map();
  const __ext_listeners = [];

  function __ext_randomString(len = 16) {
    const bytes = crypto.getRandomValues(new Uint8Array(len));
    return Array.from(bytes)
      .map(b => b.toString(36).padStart(2, '0'))
      .join('')
      .substring(0, len);
  }

  // Encode values for messaging (handles null, undefined, and everything else)
  function __ext_encodeForMessaging(value) {
    if (value === null) {
      return { value: "null" };
    }
    if (value === undefined) {
      return { value: "undefined" };
    }
    // Everything else gets JSON stringified
    // This handles Date, RegExp, objects, arrays, primitives, etc.
    return { json: JSON.stringify(value) };
  }

  // Decode values from messaging
  function __ext_decodeFromMessaging(encoded) {
    if (!encoded || typeof encoded !== 'object') {
      console.error('Invalid message encoding: expected object, got', typeof encoded, encoded);
      throw new Error('Invalid message encoding: expected object');
    }
    
    if ('value' in encoded) {
      if (encoded.value === "null") return null;
      if (encoded.value === "undefined") return undefined;
      
      console.error('Invalid message encoding: unknown value type', encoded.value);
      throw new Error(`Invalid message encoding: unknown value type "${encoded.value}"`);
    }
    
    if ('json' in encoded) {
      try {
        return JSON.parse(encoded.json);
      } catch (e) {
        console.error('Invalid message encoding: JSON parse error', e, encoded.json);
        throw new Error(`Invalid message encoding: JSON parse error - ${e.message}`);
      }
    }
    
    console.error('Invalid message encoding: missing required field (value or json)', encoded);
    throw new Error('Invalid message encoding: missing required field (value or json)');
  }

  const __ext_post = window.webkit.messageHandlers;

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
            // Result comes as a JSON string from Swift, parse it first
            const parsedResult = JSON.parse(result);
            const decoded = __ext_decodeFromMessaging(parsedResult);
            cb(decoded);
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
  Object.defineProperty(window, 'chrome', {
    value: { runtime },
    writable: false,
    configurable: false,
    enumerable: false
  });

  Object.freeze(window.chrome);
  true;
})();