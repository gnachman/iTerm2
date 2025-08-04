// geolocation-bridge.js
// JavaScript bridge for Geolocation API in WKWebView
// Overrides the native navigator.geolocation API to bridge to native Core Location

(function() {
    'use strict';
    try {
        // Generate a cryptographically secure random token for this session
        // This token must be included in all callbacks from native code
        const sessionSecret = "{{SECRET}}";

        // Store original geolocation if it exists
        const originalGeolocation = navigator.geolocation;

        // Store original permissions API if it exists
        const originalPermissions = navigator.permissions;

        // Permission state - will be updated by native code
        let permissionState = 'prompt'; // 'prompt', 'granted', 'denied'

        // Track all PermissionStatus objects for change notifications
        const permissionStatusObjects = new Set();

        // Active watch operations
        const activeWatches = new Map();
        let watchCounter = 0;

        // Pending operations
        const pendingOperations = new Map();
        let operationCounter = 0;

        // Position cache for efficiency
        let cachedPosition = null;
        let cacheTimestamp = 0;
        const CACHE_DURATION = 30000; // 30 seconds
        let cacheExpiryTimer = null;

        // Validate coordinates object
        function validateCoordinates(coords) {
            if (!coords || typeof coords !== 'object') return false;
            const required = ['latitude', 'longitude', 'accuracy', 'altitude', 'altitudeAccuracy', 'heading', 'speed'];
            return required.every(prop => typeof coords[prop] === 'number' || coords[prop] === null);
        }

        // Create GeolocationPosition object
        function createPosition(coords, timestamp) {
            if (!validateCoordinates(coords)) {
                throw new Error('Invalid coordinates data');
            }
            
            return Object.freeze({
                coords: Object.freeze({
                    latitude: coords.latitude,
                    longitude: coords.longitude,
                    altitude: coords.altitude,
                    accuracy: coords.accuracy,
                    altitudeAccuracy: coords.altitudeAccuracy,
                    heading: coords.heading,
                    speed: coords.speed
                }),
                timestamp: timestamp == null ? Date.now() : timestamp
            });
        }

        // Create spec-compliant PositionError class
        class iTermPositionError extends Error {
            constructor(code, message) {
                super(message);
                this.name = 'PositionError';
                
                // Define readonly code property
                Object.defineProperty(this, 'code', {
                    value: code,
                    writable: false,
                    configurable: false,
                    enumerable: true
                });
                
                // Define readonly message property (override Error's writable message)
                Object.defineProperty(this, 'message', {
                    value: message,
                    writable: false,
                    configurable: false,
                    enumerable: true
                });
            }
            
            // Static constants as per spec
            static get PERMISSION_DENIED() { return 1; }
            static get POSITION_UNAVAILABLE() { return 2; }
            static get TIMEOUT() { return 3; }
        }
        
        // Create GeolocationPositionError object
        function createPositionError(code, message) {
            return Object.freeze(new iTermPositionError(code, message));
        }

        // Validate options object
        function validateOptions(options) {
            if (!options) return {};
            
            const validatedOptions = {};
            if (typeof options.enableHighAccuracy === 'boolean') {
                validatedOptions.enableHighAccuracy = options.enableHighAccuracy;
            }
            if (typeof options.timeout === 'number' && options.timeout >= 0) {
                validatedOptions.timeout = Math.min(options.timeout, 600000); // Max 10 minutes
            }
            if (typeof options.maximumAge === 'number' && options.maximumAge >= 0) {
                validatedOptions.maximumAge = Math.min(options.maximumAge, 3600000); // Max 1 hour
            }
            
            return validatedOptions;
        }

        // Check if cached position is still valid
        function isCachedPositionValid(maximumAge = 0) {
            if (!cachedPosition) return false;
            const age = Date.now() - cacheTimestamp;
            return age <= maximumAge;
        }

        // Set up cache expiry timer
        function setCacheExpiryTimer() {
            // Clear any existing timer
            if (cacheExpiryTimer) {
                clearTimeout(cacheExpiryTimer);
            }
            
            // Set timer to clear cache after CACHE_DURATION
            cacheExpiryTimer = setTimeout(() => {
                cachedPosition = null;
                cacheTimestamp = 0;
                cacheExpiryTimer = null;
            }, CACHE_DURATION);
        }

        // Clear cache and timer
        function clearCacheAndTimer() {
            if (cacheExpiryTimer) {
                clearTimeout(cacheExpiryTimer);
                cacheExpiryTimer = null;
            }
            cachedPosition = null;
            cacheTimestamp = 0;
        }

        // Send message to native code with error handling
        function sendMessage(message) {
            if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.iTermGeolocation) {
                throw createPositionError(2, 'Geolocation service unavailable');
            }
            
            try {
                message.sessionSecret = sessionSecret;
                window.webkit.messageHandlers.iTermGeolocation.postMessage(message);
            } catch (error) {
                throw createPositionError(2, 'Failed to communicate with geolocation service: ' + error.message);
            }
        }

        // Custom geolocation implementation
        const iTermGeolocation = {
            getCurrentPosition: function(successCallback, errorCallback, options) {
                console.log("getCurrentPosition called")
                // Validate callbacks
                if (typeof successCallback !== 'function') {
                    console.log("getCurrentPosition: successCallback not a function")
                    throw new TypeError('successCallback must be a function');
                }
                if (errorCallback !== undefined && typeof errorCallback !== 'function') {
                    console.log("getCurrentPosition: errorCallback not a function")
                    throw new TypeError('errorCallback must be a function or undefined');
                }

                const validatedOptions = validateOptions(options);
                const operationId = ++operationCounter;

                // Check permission first
                if (permissionState === 'denied') {
                    console.log("getCurrentPosition: permission denied")
                    if (errorCallback) {
                        setTimeout(() => {
                            errorCallback(createPositionError(1, 'User denied the request for Geolocation.'));
                        }, 0);
                    }
                    return;
                }

                // Check cache if maximumAge allows it
                if (validatedOptions.maximumAge && isCachedPositionValid(validatedOptions.maximumAge)) {
                    console.log("getCurrentPosition: sending cached value")
                    setTimeout(() => {
                        successCallback(cachedPosition);
                    }, 0);
                    return;
                }

                // Store pending operation
                pendingOperations.set(operationId, {
                    type: 'getCurrentPosition',
                    successCallback: successCallback,
                    errorCallback: errorCallback,
                    options: validatedOptions
                });

                // Set timeout if specified
                if (validatedOptions.timeout) {
                    console.log("getCurrentPosition: start timer")
                    setTimeout(() => {
                        console.log("getCurrentPosition: timer fired")
                        const operation = pendingOperations.get(operationId);
                        if (operation && operation.errorCallback) {
                            pendingOperations.delete(operationId);
                            
                            // Cancel the native request
                            try {
                                sendMessage({
                                    type: 'cancelOperation',
                                    operationId: operationId
                                });
                            } catch (error) {
                                console.warn('Failed to send cancel message to native:', error);
                            }
                            
                            operation.errorCallback(createPositionError(3, 'Timeout expired'));
                        }
                    }, validatedOptions.timeout);
                }

                // Send request to native code
                try {
                    console.log("getCurrentPosition: send getCurrentPosition message")
                    sendMessage({
                        type: 'getCurrentPosition',
                        operationId: operationId,
                        options: validatedOptions
                    });
                } catch (error) {
                    pendingOperations.delete(operationId);
                    if (errorCallback) {
                        setTimeout(() => {
                            errorCallback(error);
                        }, 0);
                    }
                }
            },

            watchPosition: function(successCallback, errorCallback, options) {
                // Validate callbacks
                if (typeof successCallback !== 'function') {
                    throw new TypeError('successCallback must be a function');
                }
                if (errorCallback !== undefined && typeof errorCallback !== 'function') {
                    throw new TypeError('errorCallback must be a function or undefined');
                }

                const validatedOptions = validateOptions(options);
                const watchId = ++watchCounter;

                // Check permission first
                if (permissionState === 'denied') {
                    if (errorCallback) {
                        setTimeout(() => {
                            errorCallback(createPositionError(1, 'User denied the request for Geolocation.'));
                        }, 0);
                    }
                    return watchId;
                }

                // Store watch operation
                activeWatches.set(watchId, {
                    successCallback: successCallback,
                    errorCallback: errorCallback,
                    options: validatedOptions
                });

                // Send watch request to native code
                try {
                    sendMessage({
                        type: 'watchPosition',
                        watchId: watchId,
                        options: validatedOptions
                    });
                } catch (error) {
                    activeWatches.delete(watchId);
                    if (errorCallback) {
                        setTimeout(() => {
                            errorCallback(error);
                        }, 0);
                    }
                }

                return watchId;
            },

            clearWatch: function(watchId) {
                if (typeof watchId !== 'number' || !activeWatches.has(watchId)) {
                    return;
                }

                activeWatches.delete(watchId);

                // Clear cache and timer if no more active watches
                if (activeWatches.size === 0) {
                    clearCacheAndTimer();
                }

                // Send clear watch request to native code
                try {
                    sendMessage({
                        type: 'clearWatch',
                        watchId: watchId
                    });
                } catch (error) {
                    console.warn('Failed to clear watch:', error);
                }
            }
        };

        // Copy any additional properties from original geolocation
        if (originalGeolocation) {
            const propsToSkip = new Set(['getCurrentPosition', 'watchPosition', 'clearWatch']);
            
            for (const prop of Object.getOwnPropertyNames(originalGeolocation)) {
                if (!propsToSkip.has(prop)) {
                    try {
                        const descriptor = Object.getOwnPropertyDescriptor(originalGeolocation, prop);
                        if (descriptor && (descriptor.value !== undefined || descriptor.get !== undefined)) {
                            Object.defineProperty(iTermGeolocation, prop, descriptor);
                        }
                    } catch (e) {
                        // Ignore errors for non-configurable properties
                    }
                }
            }
        }

        // Freeze the geolocation object
        Object.freeze(iTermGeolocation);

        // Replace navigator.geolocation
        Object.defineProperty(navigator, 'geolocation', {
            value: iTermGeolocation,
            writable: false,
            configurable: false,
            enumerable: true
        });

        // Expose PositionError globally for instanceof checks
        if (!window.PositionError) {
            Object.defineProperty(window, 'PositionError', {
                value: iTermPositionError,
                writable: false,
                configurable: false,
                enumerable: false
            });
        }

        // Create a proper PermissionStatus object for geolocation
        function createGeolocationPermissionStatus(state) {
            const ps = {};
            
            // Make state configurable (so we can update it later) but not writable
            Object.defineProperty(ps, 'state', { 
                value: state, 
                writable: false, 
                configurable: true,
                enumerable: true
            });
            
            // Make name read-only and non-configurable (prevent monkey-patching)
            Object.defineProperty(ps, 'name', { 
                value: 'geolocation', 
                writable: false, 
                configurable: false,
                enumerable: true
            });
            
            // onchange should be writable but non-configurable (per spec)
            Object.defineProperty(ps, 'onchange', {
                value: null,
                writable: true,
                configurable: false,
                enumerable: true
            });
            
            // Store weak reference for change notifications
            permissionStatusObjects.add(new WeakRef(ps));
            
            // Don't freeze - we need state to remain configurable for updates
            return ps;
        }

        // Override navigator.permissions.query for geolocation consistency
        if (originalPermissions && originalPermissions.query) {
            const iTermPermissions = {};

            // Copy all properties except query from the original permissions object
            for (const prop of Object.getOwnPropertyNames(originalPermissions)) {
                if (prop !== 'query') {
                    try {
                        const descriptor = Object.getOwnPropertyDescriptor(originalPermissions, prop);
                        if (descriptor && (descriptor.value !== undefined || descriptor.get !== undefined)) {
                            Object.defineProperty(iTermPermissions, prop, descriptor);
                        }
                    } catch (e) {
                        // Ignore errors for non-configurable properties
                    }
                }
            }

            // Explicitly override query method
            iTermPermissions.query = function(permissionDescriptor) {
                // Handle geolocation permission queries
                if (permissionDescriptor && permissionDescriptor.name === 'geolocation') {
                    return Promise.resolve(createGeolocationPermissionStatus(permissionState));
                }
                
                // For all other permissions, use the original implementation
                return originalPermissions.query.call(originalPermissions, permissionDescriptor);
            };

            // Replace navigator.permissions
            Object.defineProperty(navigator, 'permissions', {
                value: Object.freeze(iTermPermissions),
                writable: false,
                configurable: false,
                enumerable: true
            });
        }

        // Create handler methods that validate the session secret
        function createSecureHandler(methodName, implementation) {
            return function() {
                // First argument must always be the session secret
                const providedSecret = arguments[0];
                if (providedSecret !== sessionSecret) {
                    console.error('iTermGeolocationHandler: Invalid session secret for', methodName);
                    return;
                }

                // Call the actual implementation with remaining arguments
                const args = Array.prototype.slice.call(arguments, 1);
                return implementation.apply(this, args);
            };
        }

        // Handler methods for native code callbacks
        const handlerMethods = {
            // Update permission state
            setPermission: createSecureHandler('setPermission', function(permission) {
                const validPermissions = ['prompt', 'granted', 'denied'];
                if (validPermissions.includes(permission)) {
                    const oldState = permissionState;
                    permissionState = permission;
                    
                    // Notify all tracked PermissionStatus objects if state changed
                    if (oldState !== permission) {
                        // Clean up dead WeakRefs and notify live objects
                        const deadRefs = new Set();
                        
                        for (const weakRef of permissionStatusObjects) {
                            const ps = weakRef.deref();
                            if (ps === undefined) {
                                // Object was garbage collected
                                deadRefs.add(weakRef);
                            } else {
                                // Update the state property (it's configurable)
                                Object.defineProperty(ps, 'state', { 
                                    value: permission, 
                                    writable: false, 
                                    configurable: true 
                                });
                                
                                // Fire onchange event if handler is set
                                if (typeof ps.onchange === 'function') {
                                    try {
                                        ps.onchange(new Event('change'));
                                    } catch (e) {
                                        console.error('Error in permission status onchange handler:', e);
                                    }
                                }
                            }
                        }
                        
                        // Remove dead WeakRefs
                        for (const deadRef of deadRefs) {
                            permissionStatusObjects.delete(deadRef);
                        }
                    }
                }
            }),

            // Handle successful position response
            handlePositionSuccess: createSecureHandler('handlePositionSuccess', function(operationId, coords, timestamp) {
                console.log("handlePositionSuccess called", coords);
                try {
                    const position = createPosition(coords, timestamp);
                    
                    // Update cache and set expiry timer
                    cachedPosition = position;
                    cacheTimestamp = Date.now();
                    setCacheExpiryTimer();
                    
                    const operation = pendingOperations.get(operationId);
                    if (operation && operation.successCallback) {
                        pendingOperations.delete(operationId);
                        operation.successCallback(position);
                    }
                } catch (error) {
                    console.error('Error handling position success:', error);
                    const operation = pendingOperations.get(operationId);
                    if (operation && operation.errorCallback) {
                        pendingOperations.delete(operationId);
                        operation.errorCallback(createPositionError(2, 'Invalid position data'));
                    }
                }
            }),

            // Handle position error
            handlePositionError: createSecureHandler('handlePositionError', function(operationId, code, message) {
                const operation = pendingOperations.get(operationId);
                if (operation && operation.errorCallback) {
                    pendingOperations.delete(operationId);
                    operation.errorCallback(createPositionError(code, message));
                }
            }),

            // Handle watch position update
            handleWatchPositionUpdate: createSecureHandler('handleWatchPositionUpdate', function(watchId, coords, timestamp) {
                try {
                    const position = createPosition(coords, timestamp);
                    
                    // Update cache and set expiry timer
                    cachedPosition = position;
                    cacheTimestamp = Date.now();
                    setCacheExpiryTimer();
                    
                    const watch = activeWatches.get(watchId);
                    if (watch && watch.successCallback) {
                        watch.successCallback(position);
                    }
                } catch (error) {
                    console.error('Error handling watch position update:', error);
                    const watch = activeWatches.get(watchId);
                    if (watch && watch.errorCallback) {
                        watch.errorCallback(createPositionError(2, 'Invalid position data'));
                    }
                }
            }),

            // Handle watch error
            handleWatchError: createSecureHandler('handleWatchError', function(watchId, code, message) {
                const watch = activeWatches.get(watchId);
                if (watch && watch.errorCallback) {
                    watch.errorCallback(createPositionError(code, message));
                }
                
                // Remove the failed watch
                activeWatches.delete(watchId);
                
                // Clear cache and timer if no more active watches
                if (activeWatches.size === 0) {
                    clearCacheAndTimer();
                }
            })
        };

        // Create the handler object and lock it down
        Object.defineProperty(window, 'iTermGeolocationHandler', {
            value: Object.freeze(Object.create(null, {
                setPermission: {
                    value: handlerMethods.setPermission,
                    writable: false,
                    configurable: false,
                    enumerable: true
                },
                handlePositionSuccess: {
                    value: handlerMethods.handlePositionSuccess,
                    writable: false,
                    configurable: false,
                    enumerable: true
                },
                handlePositionError: {
                    value: handlerMethods.handlePositionError,
                    writable: false,
                    configurable: false,
                    enumerable: true
                },
                handleWatchPositionUpdate: {
                    value: handlerMethods.handleWatchPositionUpdate,
                    writable: false,
                    configurable: false,
                    enumerable: true
                },
                handleWatchError: {
                    value: handlerMethods.handleWatchError,
                    writable: false,
                    configurable: false,
                    enumerable: true
                }
            })),
            writable: false,
            configurable: false,
            enumerable: false
        });

    } catch (err) {
        console.error(
            '[GeolocationBridge:init error]',
            'message:', err.message,
            'stack:', err.stack
        );
    }
})();
