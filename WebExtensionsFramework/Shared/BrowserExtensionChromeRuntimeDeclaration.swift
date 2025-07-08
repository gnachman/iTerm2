//
//  BrowserExtensionChromeRuntimeDeclaration.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/6/25.
//

func makeChromeRuntime(inputs: APIInputs) -> Namespace {
    // NOTE: When you change this, you must re-run `swift run APIGenerator` to generate new Swift protocols.
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

