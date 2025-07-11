//
//  BrowserExtensionChromeRuntimeDeclaration.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/6/25.
//

// List of all Chrome APIs to generate
let chromeAPIs: [APIDefinition] = [
    APIDefinition(name: "runtime", templateName: "chrome-runtime-api", generator: makeChromeRuntime),
    APIDefinition(name: "storage", templateName: "chrome-storage-api", generator: makeChromeStorageOnly)
]


func makeChromeRuntime(inputs: APIInputs) -> APISequence {
    APISequence {
        // NOTE: When you change this, you must re-run `swift run APIGenerator` to generate new Swift protocols.
        // This creates the top-level namespace that gets embedded into both "chrome" and "browser"
        Namespace("runtime", freeze: false, preventExtensions: true) {
            Constant("id", inputs.extensionId)
            AsyncFunction("getPlatformInfo", returns: PlatformInfo.self) {}
            VariableArgsFunction("sendMessage", returns: AnyJSONCodable.self)
            ConfigurableProperty("lastError", getter: "return undefined;")

            Namespace("onMessage", freeze: false, preventExtensions: true, isTopLevel: false) {
                PureJSFunction("addListener",
                """
                addListener(listener) {
                    __ext_listeners.push({ "external": false, "callback": listener });
                }
                """)
                PureJSFunction("removeListener",
                """
                removeListener(listener) {
                    const idx = __ext_listeners.findIndex(entry =>
                        entry.external === false &&
                        entry.callback === listener);
                    if (idx !== -1) {
                        __ext_listeners.splice(idx, 1);
                    }
                }
                """
                )
                PureJSFunction("hasListener",
                """
                hasListener(listener) {
                    return __ext_listeners.some(entry =>
                        entry.external === false &&
                        entry.callback === listener);
                }
                """
                )
            }
        }
    }
}

func makeChromeStorage(inputs: APIInputs) -> APISequence {
    APISequence {
        if !inputs.trusted {
            InlineJavascript("""
                let sessionAllowed = false;
                Object.defineProperty(window, '__ext_setSessionAllowed', {
                    value: function(flag, token) {
                        if (token !== "\(inputs.setAccessLevelToken)") {
                            console.error("__ext_setSessionAllowed: token mismatch");
                            return;
                        }
                        if (typeof flag != "boolean") {
                            console.error("__ext_setSessionAllowed: wrong type for flag:", typeof flag);
                            return;
                        }
                        sessionAllowed = flag;
                    },
                    writable: false,
                    configurable: false,
                    enumerable: false
                });
            """)
            InlineJavascript("""
                let localAllowed = true;
                Object.defineProperty(window, '__ext_setLocalAllowed', {
                    value: function(flag, token) {
                        if (token !== "\(inputs.setAccessLevelToken)") {
                            console.error("__ext_setLocalAllowed: token mismatch");
                            return;
                        }
                        if (typeof flag != "boolean") {
                            console.error("__ext_setLocalAllowed: wrong type for flag:", typeof flag);
                            return;
                        }
                        localAllowed = flag;
                    },
                    writable: false,
                    configurable: false,
                    enumerable: false
                });
            """)
            InlineJavascript("""
                let syncAllowed = true;
                Object.defineProperty(window, '__ext_setSyncAllowed', {
                    value: function(flag, token) {
                        if (token !== "\(inputs.setAccessLevelToken)") {
                            console.error("__ext_setSyncAllowed: token mismatch");
                            return;
                        }
                        if (typeof flag != "boolean") {
                            console.error("__ext_setSyncAllowed: wrong type for flag:", typeof flag);
                            return;
                        }
                        syncAllowed = flag;
                    },
                    writable: false,
                    configurable: false,
                    enumerable: false
                });
            """)
        }
        Namespace("storage", freeze: false, preventExtensions: true, jsname: inputs.trusted ? nil : "impl") {
            makeMutableStorageArea("local", hasSetAccessLevel: true)
            makeMutableStorageArea("sync", hasSetAccessLevel: true)
            makeMutableStorageArea("session", hasSetAccessLevel: true)
            makeReadOnlyStorageArea("managed")

            Namespace("onChanged", freeze: false, preventExtensions: true, isTopLevel: false) {
                PureJSFunction("addListener",
                """
                addListener(listener) {
                    if (!window.__ext_storageListeners) {
                        window.__ext_storageListeners = [];
                    }
                    __ext_storageListeners.push(listener);
                }
                """)
                PureJSFunction("removeListener",
                """
                removeListener(listener) {
                    if (!window.__ext_storageListeners) return;
                    const idx = __ext_storageListeners.findIndex(l => l === listener);
                    if (idx !== -1) {
                        __ext_storageListeners.splice(idx, 1);
                    }
                }
                """
                )
                PureJSFunction("hasListener",
                """
                hasListener(listener) {
                    if (!window.__ext_storageListeners) return false;
                    return __ext_storageListeners.includes(listener);
                }
                """
                )
            }
            if !inputs.trusted {
                JSProxy("""
                const storage = new Proxy({}, {
                  has(_, prop) {
                    if (prop === 'session' && !sessionAllowed) {
                      return false;
                    }
                    if (prop === 'sync' && !syncAllowed) {
                      return false;
                    }
                    if (prop === 'local' && !localAllowed) {
                      return false;
                    }
                    const result = Reflect.has(impl, prop);
                    return result;
                  },

                  get(_, prop) {
                    if (prop === 'session' && !sessionAllowed) {
                      return undefined;
                    }
                    if (prop === 'sync' && !syncAllowed) {
                      return undefined;
                    }
                    if (prop === 'local' && !localAllowed) {
                      return undefined;
                    }
                    if (Reflect.has(impl, prop)) {
                      const v = impl[prop];
                      if (typeof v === 'function') {
                        return v.bind(impl);
                      }
                      return v;
                    }
                    return undefined;
                  },

                  // if code does `for (let k in storage)` or Object.keys(storage)
                  ownKeys() {
                    const keys = Reflect.ownKeys(impl);
                    const result = keys.filter(key => {
                        if (key === 'session' && !sessionAllowed) {
                            return false;
                        }
                        if (key === 'sync' && !syncAllowed) {
                            return false;
                        }
                        if (key === 'local' && !localAllowed) {
                            return false;
                        }
                        return true;
                    });
                    return result;
                  },

                  getOwnPropertyDescriptor(_, prop) {
                    if (prop === 'session' && !sessionAllowed) {
                      return undefined;
                    }
                    if (prop === 'sync' && !syncAllowed) {
                      return undefined;
                    }
                    if (prop === 'local' && !localAllowed) {
                      return undefined;
                    }
                    const desc = Reflect.getOwnPropertyDescriptor(impl, prop);
                    if (desc) {
                      // allow deletion/redefinition traps to work
                      desc.configurable = true;
                    }
                    return desc;
                  },

                  set()            { throw new Error('chrome.storage is sealed'); },
                  defineProperty() { throw new Error('chrome.storage is sealed'); },
                  deleteProperty() { throw new Error('chrome.storage is sealed'); }
                });
                """)
            }
        }
    }
}

func makeMutableStorageArea(_ areaName: String, hasSetAccessLevel: Bool) -> Namespace {
    Namespace(areaName, freeze: false, preventExtensions: true, isTopLevel: false) {
        AsyncFunction("get", returns: StringToJSONObject.self, init: [("storageManager", "BrowserExtensionStorageManager")]) {
            Argument("keys", type: AnyJSONCodable?.self, transform: JSONEncodeDictionaryValuesTransform)
        }
        AsyncFunction("set", returns: Void.self, init: [("storageManager", "BrowserExtensionStorageManager")]) {
            JSONStringDictArgument("items")
        }
        AsyncFunction("remove", returns: Void.self, init: [("storageManager", "BrowserExtensionStorageManager")]) {
            Argument("keys", type: AnyJSONCodable.self, transform: JSONNoTransform)
        }
        AsyncFunction("clear", returns: Void.self, init: [("storageManager", "BrowserExtensionStorageManager")]) {}
        if hasSetAccessLevel {
            AsyncFunction("setAccessLevel", returns: Void.self, init: [("storageManager", "BrowserExtensionStorageManager")]) {
                Argument("details", type: [String: String].self)
            }
        }
    }
}

func makeReadOnlyStorageArea(_ areaName: String) -> Namespace {
    Namespace(areaName, freeze: false, preventExtensions: true, isTopLevel: false) {
        AsyncFunction("get", returns: StringToJSONObject.self, init: [("storageManager", "BrowserExtensionStorageManager")]) {
            Argument("keys", type: AnyJSONCodable?.self)
        }
        AsyncFunction("set", returns: Void.self, init: [("storageManager", "BrowserExtensionStorageManager")]) {
            JSONStringDictArgument("items")
        }
        AsyncFunction("remove", returns: Void.self, init: [("storageManager", "BrowserExtensionStorageManager")]) {
            Argument("keys", type: AnyJSONCodable.self)
        }
        AsyncFunction("clear", returns: Void.self, init: [("storageManager", "BrowserExtensionStorageManager")]) {}
    }
}

func makeChromeStorageOnly(inputs: APIInputs) -> APISequence {
    makeChromeStorage(inputs: inputs)
}

