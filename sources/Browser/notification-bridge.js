// notification-bridge.js
// JavaScript bridge for Web Notifications API in WKWebView
// Overrides the native Notification API to bridge to native notifications

(function() {
    'use strict';
    try {
        // Generate a cryptographically secure random token for this session
        // This token must be included in all callbacks from native code
        const sessionSecret = "{{SECRET}}";

        // Store original Notification if it exists
        const originalNotification = window.Notification;

        // Permission state - will be updated by native code
        let permissionState = 'default';

        // Pending permission requests
        const pendingPermissionRequests = new Map();
        let requestId = 0;

        // Active notifications - keyed by ID, with tag tracking
        const activeNotifications = new Map();
        const notificationsByTag = new Map();

        // Unique ID generator
        let notificationCounter = 0;
        function generateNotificationId() {
            return 'iterm_notification_' + (++notificationCounter);
        }

        // Validate permission string
        function validatePermission(permission) {
            return ['default', 'denied', 'granted'].includes(permission) ? permission : 'denied';
        }

        // Create a basic EventTarget implementation
        function createEventTarget() {
            const listeners = new Map();

            return {
                addEventListener: function(type, listener) {
                    if (!listeners.has(type)) {
                        listeners.set(type, new Set());
                    }
                    listeners.get(type).add(listener);
                },

                removeEventListener: function(type, listener) {
                    if (listeners.has(type)) {
                        listeners.get(type).delete(listener);
                    }
                },

                dispatchEvent: function(event) {
                    if (listeners.has(event.type)) {
                        for (const listener of listeners.get(event.type)) {
                            try {
                                listener.call(this, event);
                            } catch (e) {
                                console.error('Error in event listener:', e);
                            }
                        }
                    }
                    return true;
                }
            };
        }

        // Custom Notification constructor
        function iTermNotification(title, options = {}) {
            // Enforce 'new' usage
            if (!(this instanceof iTermNotification)) {
                throw new TypeError("Failed to construct 'Notification': Please use the 'new' operator, this DOM object constructor cannot be called as a function.");
            }

            // Validate title
            if (arguments.length === 0) {
                throw new TypeError("Failed to construct 'Notification': 1 argument required, but only 0 present.");
            }

            // Check permission - throw if not granted (per spec)
            if (iTermNotification.permission !== 'granted') {
                throw new DOMException("Failed to construct 'Notification': permission denied.", 'NotAllowedError');
            }

            // Set up EventTarget functionality
            const eventTarget = createEventTarget();
            Object.assign(this, eventTarget);

            // Store notification properties
            this.title = String(title);
            this.body = options.body ? String(options.body).substring(0, 1000) : ''; // Limit length
            this.icon = options.icon ? String(options.icon).substring(0, 500) : '';
            this.tag = options.tag ? String(options.tag).substring(0, 100) : '';
            this.silent = Boolean(options.silent);

            // Event handlers (legacy support)
            this.onclick = null;
            this.onshow = null;
            this.onerror = null;
            this.onclose = null;

            // Generate unique ID for this notification
            const notificationId = generateNotificationId();

            // Handle tag replacement
            if (this.tag) {
                const existingId = notificationsByTag.get(this.tag);
                if (existingId && activeNotifications.has(existingId)) {
                    // Close existing notification with same tag
                    const existingNotification = activeNotifications.get(existingId);
                    existingNotification.close();
                }
                notificationsByTag.set(this.tag, notificationId);
            }

            activeNotifications.set(notificationId, this);

            // Store ID for cleanup
            this._iTermNotificationId = notificationId;

            // Send notification request to native code
            if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.iTermNotification) {
                throw new DOMException("Failed to show notification: native bridge not available.", 'AbortError');
            }

            try {
                window.webkit.messageHandlers.iTermNotification.postMessage({
                    type: 'show',
                    id: notificationId,
                    title: this.title,
                    body: this.body,
                    icon: this.icon,
                    silent: this.silent,
                    sessionSecret: sessionSecret
                });
            } catch (error) {
                activeNotifications.delete(notificationId);
                if (this.tag) {
                    notificationsByTag.delete(this.tag);
                }
                throw new DOMException("Failed to show notification: " + error.message, 'AbortError');
            }

            // Dispatch show event asynchronously
            setTimeout(() => {
                const showEvent = new Event('show');
                this.dispatchEvent(showEvent);
                if (this.onshow) {
                    try {
                        this.onshow.call(this, showEvent);
                    } catch (e) {
                        console.error('Error in onshow handler:', e);
                    }
                }
            }, 0);

            // Auto-cleanup after 30 seconds to prevent memory leaks
            setTimeout(() => {
                if (activeNotifications.has(notificationId)) {
                    this.close();
                }
            }, 30000);
        }

        // Static permission property
        Object.defineProperty(iTermNotification, 'permission', {
            get: function() {
                return permissionState;
            },
            configurable: false,
            enumerable: true
        });

        // Static requestPermission method
        iTermNotification.requestPermission = function(callback) {
            // Return a Promise
            const promise = new Promise((resolve, reject) => {
                // If permission is already determined, resolve immediately
                if (permissionState !== 'default') {
                    const result = permissionState;
                    resolve(result);
                    if (callback) callback(result);
                    return;
                }

                // Check for native bridge availability
                if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.iTermNotification) {
                    // Keep permission state as 'default' since we can't actually request
                    // This allows pages to retry or handle the case gracefully
                    const result = 'default';
                    permissionState = result;
                    resolve(result);
                    if (callback) callback(result);
                    return;
                }

                // Generate request ID
                const currentRequestId = ++requestId;

                // Store the resolve function and callback
                pendingPermissionRequests.set(currentRequestId, {
                    resolve: resolve,
                    callback: callback
                });

                try {
                    // Send permission request to native code
                    window.webkit.messageHandlers.iTermNotification.postMessage({
                        type: 'requestPermission',
                        requestId: currentRequestId,
                        sessionSecret: sessionSecret
                    });
                } catch (error) {
                    // Clean up on error
                    pendingPermissionRequests.delete(currentRequestId);
                    const result = 'denied';
                    resolve(result);
                    if (callback) callback(result);
                }
            });

            // For compatibility with older callback-based usage
            if (callback && typeof callback === 'function') {
                promise.then(callback).catch(() => callback('denied'));
            }

            return promise;
        };

        // Method to close notification
        iTermNotification.prototype.close = function() {
            const notificationId = this._iTermNotificationId;
            if (!notificationId || !activeNotifications.has(notificationId)) {
                return;
            }

            // Send close request to native code
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.iTermNotification) {
                try {
                    window.webkit.messageHandlers.iTermNotification.postMessage({
                        type: 'close',
                        id: notificationId,
                        sessionSecret: sessionSecret
                    });
                } catch (error) {
                    console.warn('Failed to send close message to native:', error);
                }
            }

            // Clean up
            activeNotifications.delete(notificationId);
            if (this.tag) {
                notificationsByTag.delete(this.tag);
            }

            // Dispatch close event
            const closeEvent = new Event('close');
            this.dispatchEvent(closeEvent);
            if (this.onclose) {
                try {
                    this.onclose.call(this, closeEvent);
                } catch (e) {
                    console.error('Error in onclose handler:', e);
                }
            }
        };

        // Copy static properties from original Notification (excluding ones we override)
        if (originalNotification) {
            const propsToSkip = new Set(['permission', 'requestPermission', 'prototype', 'name', 'length']);

            for (const prop of Object.getOwnPropertyNames(originalNotification)) {
                if (!propsToSkip.has(prop)) {
                    try {
                        const descriptor = Object.getOwnPropertyDescriptor(originalNotification, prop);
                        if (descriptor && (descriptor.value !== undefined || descriptor.get !== undefined)) {
                            Object.defineProperty(iTermNotification, prop, descriptor);
                        }
                    } catch (e) {
                        // Ignore errors for non-configurable properties or access restrictions
                    }
                }
            }
        }

        // Freeze the constructor to prevent tampering
        Object.freeze(iTermNotification);
        Object.freeze(iTermNotification.prototype);

        // Replace the global Notification and lock it down
        Object.defineProperty(window, 'Notification', {
            value: iTermNotification,
            writable: false,
            configurable: false,
            enumerable: true
        });

        // Create handler methods that validate the session secret
        function createSecureHandler(methodName, implementation) {
            return function() {
                // First argument must always be the session secret
                const providedSecret = arguments[0];
                if (providedSecret !== sessionSecret) {
                    console.error('iTermNotificationHandler: Invalid session secret for', methodName);
                    return;
                }

                // Call the actual implementation with remaining arguments
                const args = Array.prototype.slice.call(arguments, 1);
                return implementation.apply(this, args);
            };
        }

        // Handler for native code to call - all methods require valid session secret
        const handlerMethods = {
            // Update permission state
            setPermission: createSecureHandler('setPermission', function(permission) {
                permissionState = validatePermission(permission);
            }),

            // Handle permission request response
            handlePermissionResponse: createSecureHandler('handlePermissionResponse', function(requestId, permission) {
                const validatedPermission = validatePermission(permission);
                permissionState = validatedPermission;
                const pending = pendingPermissionRequests.get(requestId);
                if (pending) {
                    pending.resolve(validatedPermission);
                    if (pending.callback) pending.callback(validatedPermission);
                    pendingPermissionRequests.delete(requestId);
                }
            }),

            // Handle notification click
            handleNotificationClick: createSecureHandler('handleNotificationClick', function(notificationId) {
                const notification = activeNotifications.get(notificationId);
                if (notification) {
                    const clickEvent = new Event('click');
                    notification.dispatchEvent(clickEvent);
                    if (notification.onclick) {
                        try {
                            notification.onclick.call(notification, clickEvent);
                        } catch (e) {
                            console.error('Error in onclick handler:', e);
                        }
                    }
                }
            }),

            // Handle notification close
            handleNotificationClose: createSecureHandler('handleNotificationClose', function(notificationId) {
                const notification = activeNotifications.get(notificationId);
                if (notification) {
                    notification.close();
                }
            })
        };

        // Lock down the handler object and its methods
        Object.defineProperty(window, 'iTermNotificationHandler', {
            value: Object.freeze(Object.create(null, {
                setPermission: {
                    value: handlerMethods.setPermission,
                    writable: false,
                    configurable: false,
                    enumerable: true
                },
                handlePermissionResponse: {
                    value: handlerMethods.handlePermissionResponse,
                    writable: false,
                    configurable: false,
                    enumerable: true
                },
                handleNotificationClick: {
                    value: handlerMethods.handleNotificationClick,
                    writable: false,
                    configurable: false,
                    enumerable: true
                },
                handleNotificationClose: {
                    value: handlerMethods.handleNotificationClose,
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
        '[NotificationBridge:init error]',
        'message:', err.message,
        'stack:', err.stack
      );
    }


})();
