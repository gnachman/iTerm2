;(function() {
  'use strict';
  
  // Use the global shared helper functions and variables
  const __ext_callbackMap = window.__ext_callbackMap;
  const __ext_randomString = window.__ext_randomString;
  const __ext_post = window.__ext_post;
  
  // Initialize storage listeners if not already done
  if (!window.__ext_storageListeners) {
    window.__ext_storageListeners = [];
  }

  {{STORAGE_BODY}}

  // Add storage to the existing chrome object
  Object.defineProperty(window.chrome, 'storage', {
    value: storage,
    writable: false,
    configurable: false,
    enumerable: true
  });

  true;
})();