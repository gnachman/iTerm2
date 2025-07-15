;(function() {
  'use strict';
  // chrome-base.js
  // Define the base chrome object that all APIs will extend
  Object.defineProperty(window, 'chrome', {
    value: {},
    writable: false,
    configurable: false,
    enumerable: false
  });

  // Shared helper functions for all Chrome APIs
  window.__ext_callbackMap = new Map();
  window.__ext_listeners = [];

  window.__ext_randomString = function(len = 16) {
    const bytes = crypto.getRandomValues(new Uint8Array(len));
    return Array.from(bytes)
      .map(b => b.toString(36).padStart(2, '0'))
      .join('')
      .substring(0, len);
  };

  // Encode values for messaging (handles null, undefined, and everything else)
  window.__ext_encodeForMessaging = function(value) {
    if (value === null) {
      return { value: "null" };
    }
    if (value === undefined) {
      return { value: "undefined" };
    }
    // Everything else gets JSON stringified
    // This handles Date, RegExp, objects, arrays, primitives, etc.
    return { json: JSON.stringify(value) };
  };

  // Decode values from messaging
  window.__ext_decodeFromMessaging = function(encoded) {
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
  };

  window.__ext_post = window.webkit.messageHandlers;

  // Storage onChanged event dispatcher
  // changes has { storageKeyString: { newValue: JSON-encoded string, oldValue: JSON-encoded string } }
  window.__EXT_fireStorageChanged__ = function(changes, areaName) {
    if (!window.__ext_storageListeners) {
      return;
    }
    
    // Call all registered onChanged listeners
    for (const listener of window.__ext_storageListeners) {
      try {
        const decodedChanges = Object.entries(changes)
          .reduce((acc, [key, change]) => {
            acc[key] = {};
            if (change.newValue !== undefined) {
              acc[key].newValue = JSON.parse(change.newValue);
            }
            if (change.oldValue !== undefined) {
              acc[key].oldValue = JSON.parse(change.oldValue);
            }
            return acc;
          }, {});
          listener(decodedChanges, areaName);
      } catch (error) {
        console.error('Error in storage onChanged listener:', error);
      }
    }
  };
  window.__EXT_jsonEncodeValues =  function transform(arg) {
        window.console.log("encode", arg === null ? "null" : arg === undefined ? "undefined" : arg.toString(), "of type", (typeof arg));
        if (arg !== null && typeof arg === 'object' && !Array.isArray(arg)) {
            return Object.fromEntries(
                Object.entries(arg).map(([key, value]) => [key, JSON.stringify(value)])
            );
        }
        return JSON.stringify(arg);
    }

   window.__EXT_strictStringify = function strictStringify(obj) {
        // reject illegal root values
        if (obj === undefined) {
            throw new TypeError(`Cannot stringify undefined value`);
        }
        if (typeof obj === 'function') {
            throw new TypeError(`Cannot stringify function at root`);
        }
        if (typeof obj === 'symbol') {
            throw new TypeError(`Cannot stringify symbol at root`);
        }

        const seen = new WeakSet();

        return JSON.stringify(obj, function replacer(key, value) {
            if (value === undefined) {
                throw new TypeError(`Cannot stringify undefined value at key "${key}"`);
            }
            if (typeof value === 'function') {
                throw new TypeError(`Cannot stringify function at key "${key}"`);
            }
            if (typeof value === 'symbol') {
                throw new TypeError(`Cannot stringify symbol at key "${key}"`);
            }

            if (value && typeof value === 'object') {
                if (seen.has(value)) {
                    throw new TypeError(`Cannot stringify circular reference at key "${key}"`);
                }
                seen.add(value);

                const syms = Object.getOwnPropertySymbols(value);
                if (syms.length > 0) {
                    throw new TypeError(`Cannot stringify symbol-keyed property at key "${key}"`);
                }
            }

            return value;
        });
    }
    window.__EXT_stringifyObjectValues = function stringifyValues(obj) {
        const result = {}
        for (const [key, value] of Object.entries(obj)) {
            result[key] = JSON.stringify(value)
        }
        return result
    }
    window.__ext_checkCallback = function validateCallback(callback) {
        if (callback != null && typeof callback !== 'function') {
            throw new TypeError(
                `expected callback to be a function, ` +
                `but got ${callback === null ? 'null' : typeof callback}`);
        }
    }

  // Don't freeze yet - APIs need to add themselves first
  true;
})();
